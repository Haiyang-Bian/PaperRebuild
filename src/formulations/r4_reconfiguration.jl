function r4_switching_variables!(model, v, c, options)
    n=c.data["network_control"]
    T=c.data["T"]
    ne=length(c.data["electric"]["edges"])
    nh=3
    u=@variable(model, [1:ne, 1:T], lower_bound=0, upper_bound=1, base_name="u_E")
    h=@variable(model, [1:nh], lower_bound=0, upper_bound=1, base_name="u_H")
    a=@variable(model, [1:ne, 1:T], lower_bound=0, upper_bound=1, base_name="a_E")
    ah=@variable(model, [1:nh], lower_bound=0, upper_bound=1, base_name="a_H")
    dir=@variable(model, [1:2nh, 1:T], lower_bound=0, upper_bound=1, base_name="u_H_arc")
    v["u_E"]=u
    v["u_H"]=h
    v["a_E"]=a
    v["a_H"]=ah
    v["u_H_arc"]=dir
    electric_plan=get(options, :electric_schedule, nothing)
    heat_plan=get(options, :heat_open, nothing)
    directions=get(options, :heat_direction, nothing)
    active_plan=get(options, :heat_active, nothing)
    allow_idle=get(options, :allow_idle, false)
    active_plan!==nothing &&
        (!allow_idle || directions!==nothing) &&
        error("循环计划只用于明确允许闲置的热网版本")
    function discrete!(vars, plan)
        if plan===nothing
            foreach(set_binary, vars)
        else
            size(plan)==size(vars) && all(x->x in (0, 1), plan) || error("离散计划形状或取值错误")
            foreach(x->fix(vars[x], plan[x]; force = true), eachindex(vars))
        end
    end
    discrete!(u, electric_plan)
    discrete!(h, heat_plan)
    if active_plan!==nothing
        discrete!(dir, active_plan)
    elseif directions===nothing
        foreach(set_binary, dir)
    else
        size(directions)==(nh, T) && all(x->x in (0, 1), directions) || error("热方向形状/取值错误")
        # 固定方向仍保留阀门状态；固定全离散计划时约束保持连续。
        for p in 1:nh, t in 1:T
            @constraint(model, dir[p, t]==directions[p, t]*h[p])
            @constraint(model, dir[p+nh, t]==(1-directions[p, t])*h[p])
        end
    end
    for p in 1:nh, t in 1:T
        if allow_idle
            @constraint(model, dir[p, t]+dir[p+nh, t]<=h[p])
        else
            @constraint(model, dir[p, t]+dir[p+nh, t]==h[p])
        end
    end
    if options.policy in (:fixed, :heat)
        for p in 1:ne, t in 1:T
            @constraint(model, u[p, t]==n["electric_initial"][p])
        end
    end
    if options.policy in (:fixed, :electric)
        for p in 1:nh
            @constraint(model, h[p]==n["heat_initial"][p])
        end
    end
    # R4-N3：变化量为二元状态的精确异或；不靠正成本促使辅助量取等。
    function xor!(x, cur, prev)
        @constraint(model, x>=cur-prev)
        @constraint(model, x>=prev-cur)
        @constraint(model, x<=cur+prev)
        @constraint(model, x<=2-cur-prev)
    end
    for p in 1:ne
        for t in 1:T
            xor!(a[p, t], u[p, t], t==1 ? n["electric_initial"][p] : u[p, t-1])
            @constraint(model, sum(a[p, k] for k in max(1, t-n["dwell_steps"]+1):t)<=1)
        end
        @constraint(model, sum(a[p, t] for t in 1:T)<=n["max_electric_actions"])
    end
    for p in 1:nh
        xor!(ah[p], h[p], n["heat_initial"][p])
    end
    # R4-N1：虚拟商品流仅证明连通，不是实际电/热流，也不固定分布资源流向。
    for (key, edges, on, nt) in (
        ("F_E", c.data["electric"]["edges"], u, T),
        ("F_H", c.data["heat"]["pipes"][1:nh], reshape(h, nh, 1), 1),
    )
        f=@variable(model, [1:length(edges), 1:nt], base_name=key)
        v[key]=f
        for t in 1:nt
            @constraint(model, sum(on[p, t] for p in eachindex(edges))==2)
            for p in eachindex(edges)
                @constraint(model, f[p, t]<=2on[p, t])
                @constraint(model, f[p, t]>=-2on[p, t])
            end
            for i in 1:3
                inc=findall(x->x["to"]==i, edges)
                out=findall(x->x["from"]==i, edges)
                @constraint(
                    model,
                    sum(f[p, t] for p in out; init = 0)-sum(f[p, t] for p in inc; init = 0)==(
                        i==1 ? 2 : -1
                    )
                )
            end
        end
    end
    return n["electric_action_cost"]*sum(a)+n["heat_action_cost"]*sum(ah)
end

"""
    build_r4_reconfiguration(case; spec=R4ReconfigurationSpec(), optimizer=nothing,
                            modes=nothing, electric_schedule=nothing,
                            heat_open=nothing, heat_direction=nothing)

构建带候选电线和成对热方向弧的第4章模型，不求解或写文件。热阀门全时域固定，
电开关逐时决定，热流方向可逐时改变且同管道至多一个方向运行。动作成本为美元/次。
电压降只对接通线路成立；断管不输运也不计冻结损耗。连通树用虚拟商品流证明。
可固定全部离散计划以供Clarabel/穷举独立参照；矩阵均为边或管道×时段。
"""
function build_r4_reconfiguration(
    c::R4Case;
    spec = R4ReconfigurationSpec(),
    optimizer = nothing,
    modes = nothing,
    electric_schedule = nothing,
    heat_open = nothing,
    heat_direction = nothing,
)
    haskey(c.data, "network_control") || error("需要显式候选网络输入")
    switching=(; policy = spec.policy, electric_schedule, heat_open, heat_direction)
    return build_r4_model(c; spec = R4Spec(electric = spec.electric), optimizer, modes, switching)
end
