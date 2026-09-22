"""
    add_r7_chp_commitment!(model, spec; fixed_u=nothing)

向调用者JuMP模型加入灾前CHP启停、P/Q容量、爬坡和热电比，不求解、不设置目标。
返回变量、公式映射和启动/期望运行费用表达式。原6-6与启动变量定义冲突，采用R7-N1/N2。
`fixed_u`只用于显式状态枚举；未提供时保留整数决策。该块为MILP/LP，不认证整个热网线性。
"""
function add_r7_chp_commitment!(m::JuMP.Model, s::R7CHPSpec; fixed_u = nothing)
    r7_chp_assert(s)
    d=s.data
    T, W, dt=d["periods"], length(d["probabilities"]), d["dt_h"]
    prefix=d["id"]
    if fixed_u===nothing
        u=@variable(m, [1:T], binary=true, base_name=prefix*"_u_CHP")
        ν_on=@variable(m, [1:T], binary=true, base_name=prefix*"_nu_on")
        ν_off=@variable(m, [1:T], binary=true, base_name=prefix*"_nu_off")
    else
        v=r7_numbers(fixed_u, (T,), "固定启停"; lo = 0, hi = 1)
        all(isinteger, v) || error("枚举启停必须为0/1")
        u=@variable(m, [1:T], lower_bound=0, upper_bound=1, base_name=prefix*"_u_CHP")
        ν_on=@variable(m, [1:T], lower_bound=0, upper_bound=1, base_name=prefix*"_nu_on")
        ν_off=@variable(m, [1:T], lower_bound=0, upper_bound=1, base_name=prefix*"_nu_off")
        prev=Float64(d["previous_commitment"])
        for t in 1:T
            fix(u[t], v[t]; force = true)
            fix(ν_on[t], max(v[t]-prev, 0); force = true)
            fix(ν_off[t], max(prev-v[t], 0); force = true)
            prev=v[t]
        end
    end
    P=@variable(m, [1:T, 1:W], lower_bound=0, upper_bound=d["P_max_MW"], base_name=prefix*"_P_CHP")
    Q=@variable(
        m,
        [1:T, 1:W],
        lower_bound=0,
        upper_bound=d["Q_max_Mvar"],
        base_name=prefix*"_Q_CHP"
    )
    H=@variable(
        m,
        [1:T, 1:W],
        lower_bound=0,
        upper_bound=d["heat_ratio"]*d["P_max_MW"],
        base_name=prefix*"_H_CHP"
    )
    cs=Dict{String,Vector{Any}}()
    add(id, c) = (push!(get!(cs, id, Any[]), c); c)
    U, D=r7_chp_steps(d["min_on_h"], dt), r7_chp_steps(d["min_off_h"], dt)
    prior_min=d[d["previous_commitment"]==1 ? "min_on_h" : "min_off_h"]
    residual_steps=r7_chp_steps(max(0, prior_min-d["previous_duration_h"]), dt)
    for t in 1:T
        before=t==1 ? d["previous_commitment"] : u[t-1]
        # 启停转移必须独立于目标成立；零启机费时仍禁止虚构启机/关机。
        add("R7-N1", @constraint(m, u[t]-before==ν_on[t]-ν_off[t]))
        add("R7-N1", @constraint(m, ν_on[t]+ν_off[t]<=1))
        add("R7-N2", @constraint(m, sum(ν_on[k] for k in max(1, t-U+1):t; init = 0.0)<=u[t]))
        add("R7-N2", @constraint(m, sum(ν_off[k] for k in max(1, t-D+1):t; init = 0.0)<=1-u[t]))
        t<=residual_steps && add("R7-N3", @constraint(m, u[t]==d["previous_commitment"]))
        if d["terminal_rule"]=="complete_within_horizon"
            t+U-1>T && add("R7-N4", @constraint(m, ν_on[t]==0))
            t+D-1>T && add("R7-N4", @constraint(m, ν_off[t]==0))
        end
        for w in 1:W
            add("6-2", @constraint(m, P[t, w]>=d["P_min_MW"]*u[t]))
            add("6-2", @constraint(m, P[t, w]<=d["P_max_MW"]*u[t]))
            add("6-3", @constraint(m, Q[t, w]>=d["Q_min_Mvar"]*u[t]))
            add("6-3", @constraint(m, Q[t, w]<=d["Q_max_Mvar"]*u[t]))
            previous=t==1 ? d["previous_P_MW"][w] : P[t-1, w]
            # R为MW/h；SU、SD是一次边界转换允许的MW，不再乘时间步。
            add(
                "6-4",
                @constraint(
                    m,
                    P[t, w]-previous<=before*d["ramp_MW_h"]*dt+(1-before)*d["startup_MW"]
                )
            )
            add(
                "6-5",
                @constraint(m, previous-P[t, w]<=u[t]*d["ramp_MW_h"]*dt+(1-u[t])*d["shutdown_MW"])
            )
            add("6-11", @constraint(m, H[t, w]==d["heat_ratio"]*P[t, w]))
        end
    end
    if d["terminal_rule"]=="complete_within_horizon" && residual_steps>T
        # 给定初始义务在窗口内无法结束；保留数学不可行，不在输入层伪造满龄状态。
        add("R7-N4", @constraint(m, 0.0*sum(u)>=1.0))
    end
    startup_cost=@expression(m, d["startup_cost_USD"]*sum(ν_on))
    running_cost=@expression(
        m,
        dt*sum(d["probabilities"][w]*d["cost_P_USD_MWh"]*P[t, w] for t in 1:T, w in 1:W)
    )
    (;
        variables = Dict(
            "u_CHP"=>u,
            "ν_on"=>ν_on,
            "ν_off"=>ν_off,
            "P_CHP"=>P,
            "Q_CHP"=>Q,
            "H_CHP"=>H,
        ),
        constraints = cs,
        startup_cost,
        running_cost,
        cost = startup_cost+running_cost,
        component_class = fixed_u===nothing ? "MILP" : "LP",
    )
end
