# 仅复制当前R7实际使用的标量仿射/变量集合约束；不把非线性约束丢弃后冒称等价。
function r7_append_linear_block!(target, source, prefix)
    vm=Dict(v=>@variable(target, base_name=prefix*"_"*name(v)) for v in all_variables(source))
    function translate(f)
        f isa Number && return Float64(f)
        f isa VariableRef && return vm[f]
        f isa AffExpr || error("R7拼接不支持该表达式类型")
        out=AffExpr(f.constant)
        for (v, a) in f.terms
            add_to_expression!(out, a, vm[v])
        end
        out
    end
    for (F, S) in list_of_constraint_types(source)
        F in (VariableRef, AffExpr) && S in (
            MOI.LessThan{Float64},
            MOI.GreaterThan{Float64},
            MOI.EqualTo{Float64},
            MOI.Interval{Float64},
            MOI.ZeroOne,
        ) || error("R7拼接遇到未声明约束类型")
        for con in all_constraints(source, F, S)
            object=constraint_object(con)
            add_constraint(target, ScalarConstraint(translate(object.func), object.set))
        end
    end
    (; variables = vm, objective = translate(objective_function(source)))
end

"""
    build_r7_planning(case; optimizer=nothing, included=nothing, fixed_commitments=nothing)

建立共享灾前决策的经济安全主问题，不优化/写文件。included=nothing纳入全部有限故障，
空向量为初始外层松弛。每个事件/故障有独立恢复块；同一块的恢复拓扑与流量保持场景共享。
只最小化正常费用；恢复块提供失供不超门槛的存在性见证，不要求其在主问题内再最小化失供。
本版正常域为给定正流、固定电拓扑；返回实际MILP/LP类型和明确范围。
"""
function build_r7_planning(
    c::R7PlanningCase;
    optimizer = nothing,
    included = nothing,
    fixed_commitments = nothing,
)
    r7_planning_assert(c)
    allpairs=r7_planning_pairs(c)
    pairs=included===nothing ? allpairs : included
    allowed=Set(r7_planning_pair_key(p) for p in allpairs)
    keys=[r7_planning_pair_key(p) for p in pairs]
    length(keys)==length(unique(keys)) && all(k->k in allowed, keys) ||
        error("故障约束不属于声明集合或重复")
    m=optimizer===nothing ? Model() : Model(optimizer)
    normal=build_r7_normal(c.normal; fixed_commitments)
    nm=r7_append_linear_block!(m, normal.model, "normal")
    nv=Dict(k=>map(v->nm.variables[v], a) for (k, a) in normal.variables)
    nc=Dict(
        id=>Dict(k=>map(v->nm.variables[v], a) for (k, a) in block.variables) for
        (id, block) in normal.chp
    )
    recovery=Any[]
    d=c.normal.data
    W=length(d["probabilities"])
    for (q, pair) in enumerate(pairs)
        event=c.specification["events"][pair.event]
        at=event["event_start"]
        T=event["periods"]
        template=r7_event_template(c, pair.event)
        rec=build_r7_recovery(template, pair.fault; boundary_variables = true)
        rm=r7_append_linear_block!(m, rec.model, "event_$(pair.event)_fault_$q")
        rv=Dict(k=>map(v->rm.variables[v], a) for (k, a) in rec.variables)
        rp=Dict(k=>map(v->rm.variables[v], a) for (k, a) in rec.boundary_parameters)
        # R7-M1：绝不固定为上轮灾前解；每个块都链接本轮同一正常变量。
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
        for side in ("S", "R"), w in 1:W
            @constraint(m, rp["E_$(side)_before"][w]==sum(nv["E_pipe_$side"][:, at, w]))
        end
        for a in eachindex(d["heat"]["pipes"]), t in 1:T
            @constraint(m, rp["m_normal"][a, t]==d["heat"]["pipes"][a]["normal_flow_kg_s"][at+t-1])
        end
        @constraint(m, rm.objective<=event["loss_limit_MWh"])
        push!(recovery, (; pair, variables = rv, parameters = rp, loss = rm.objective))
    end
    @objective(m, Min, nm.objective)
    (;
        model = m,
        normal_variables = nv,
        chp_variables = nc,
        recovery,
        included = collect(pairs),
        all_pairs = allpairs,
        model_class = any(is_binary, all_variables(m)) ? "MILP" : "LP",
    )
end
