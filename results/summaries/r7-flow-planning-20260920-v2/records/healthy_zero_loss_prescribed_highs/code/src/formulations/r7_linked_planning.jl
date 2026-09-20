"""
    build_r7_linked_planning(case, spec; optimizer=nothing, included=nothing,
                            fixed_commitments=nothing, deadline=Inf)

R7-L2：共享正常决策的详细输运安全规划。included=nothing纳入全部允许故障，空集合为正常基准。
每个恢复块保留设备、电网和边界，热状态由同一正常入口历史决定；节点采用子步平均、零节点容积。
给定流量时实际约束为仿射/整数；返回正常与恢复变量及参数连接，不求解、不写文件。
本条件域不代表论文完整变流量/水力模型，恢复块只提供门槛内存在性见证。
"""
function build_r7_linked_planning(
    c::R7PlanningCase,
    s;
    optimizer = nothing,
    included = nothing,
    fixed_commitments = nothing,
    deadline = Inf,
)
    r7_linked_spec_check(c, s)
    time()<deadline || error("linked_build_deadline")
    allpairs=r7_planning_pairs(c)
    pairs=included===nothing ? allpairs : collect(included)
    keys=r7_planning_pair_key.(pairs)
    length(keys)==length(unique(keys)) && all(k->k in r7_planning_pair_key.(allpairs), keys) ||
        error("详细规划故障集合非法")
    m=optimizer===nothing ? Model() : Model(optimizer)
    normal=build_r7_normal(c.normal; fixed_commitments)
    nm=r7_append_linear_block!(m, normal.model, "normal")
    nv=Dict(k=>map(v->nm.variables[v], a) for (k, a) in normal.variables)
    nc=Dict(
        id=>Dict(k=>map(v->nm.variables[v], a) for (k, a) in block.variables) for
        (id, block) in normal.chp
    )
    d=c.normal.data
    W=length(d["probabilities"])
    recovery=Any[]
    for (index, pair) in enumerate(pairs)
        time()<deadline || error("linked_build_deadline")
        e=c.specification["events"][pair.event]
        at, T=e["event_start"], e["periods"]
        template=r7_linked_template(c, s, pair)
        maps=Dict(
            (a, side, w)=>r7_linked_pipe_map(c, s, pair, a, side, w; deadline) for
            a in eachindex(d["heat"]["pipes"]) for side in ("S", "R") for w in 1:W
        )
        function history(model)
            prefix=Dict(
                (a, side, w)=>[
                    @variable(model, base_name="normal_inlet[$a,$side,$w,$t]") for t in 1:(at-1)
                ] for a in eachindex(d["heat"]["pipes"]) for side in ("S", "R") for w in 1:W
            )
            (; maps, prefix)
        end
        b=build_r7_transport_recovery(
            template.case,
            pair.fault,
            template.spec;
            boundary_variables = true,
            history,
            deadline,
        )
        rm=r7_append_linear_block!(m, b.model, "event_$(pair.event)_fault_$index")
        rv=Dict(k=>map(v->rm.variables[v], a) for (k, a) in b.variables)
        tv=Dict(k=>map(v->rm.variables[v], a) for (k, a) in b.thermal_variables)
        rp=Dict(k=>map(v->rm.variables[v], a) for (k, a) in b.boundary_parameters)
        prefix=Dict(k=>map(v->rm.variables[v], a) for (k, a) in b.history.prefix)
        for ((a, side, w), pvars) in prefix
            node=d["heat"]["pipes"][a][side=="S" ? "from" : "to"]
            for t in eachindex(pvars)
                @constraint(m, pvars[t]==nv["τ_$side"][node, t, w])
            end
        end
        # 所有事件共用同一正常控制；事件之间是可能分支，不连续扣减正常储备。
        for (g, dev) in enumerate(d["devices"])
            if dev["kind"]=="CHP"
                u=nc[dev["id"]]["u_CHP"]
                for t in 1:T
                    @constraint(m, rp["u"][g, t]==u[at+t-1])
                end
                before=at==1 ? dev["previous_commitment"] : u[at-1]
                @constraint(m, rp["u_before"][g]==before)
                for w in 1:W
                    previous=at==1 ? dev["previous_P_MW"][w] : nv["P"][g, at-1, w]
                    @constraint(m, rp["P_before"][g, w]==previous)
                end
            elseif dev["kind"]=="BES"
                for w in 1:W
                    @constraint(m, rp["E_before"][g, w]==nv["E_BES"][g, at, w])
                end
            end
        end
        # 删除代理热方程后这两个参数不决定详细热状态，仅保留明确的库存恒等连接。
        for side in ("S", "R"), w in 1:W
            @constraint(m, rp["E_$(side)_before"][w]==sum(nv["E_pipe_$side"][:, at, w]))
        end
        for a in eachindex(d["heat"]["pipes"]), t in 1:T
            @constraint(m, rp["m_normal"][a, t]==d["heat"]["pipes"][a]["normal_flow_kg_s"][at+t-1])
        end
        @constraint(m, rm.objective<=e["loss_limit_MWh"])
        push!(
            recovery,
            (; pair, variables = rv, thermal_variables = tv, prefix, loss = rm.objective),
        )
    end
    time()<deadline || error("linked_build_deadline")
    @objective(m, Min, nm.objective)
    (;
        model = m,
        normal_variables = nv,
        chp_variables = nc,
        recovery,
        included = pairs,
        all_pairs = allpairs,
        model_class = any(is_binary, all_variables(m)) ? "MILP" : "LP",
    )
end
