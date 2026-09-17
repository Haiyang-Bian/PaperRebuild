# 冻结尺度来自输入边界；不参与A1容差定义。
function r3_physical_scales(c)
    d, h, e=c.data, c.data["heat"], c.data["electric"]
    heat=max(
        1.0,
        sum(
            g["P_max"]*g["heat_ratio"] for g in d["devices"] if g["kind"] in ("CHP", "EB");
            init = 0.0,
        ),
        maximum(sum(n["H_MW"][t] for n in h["nodes"]) for t in 1:d["T"]),
    )
    temperature=max(1.0, diff(h["S_bounds_K"])[1], diff(h["R_bounds_K"])[1])
    electric=[
        e["v_max_pu"]^2*edge["ell_max_pu"]+2(e["grid_max_MW"]/e["base_MVA"])^2 for
        edge in e["edges"]
    ]
    return (; heat, temperature, electric)
end

# 独立数值残差：直接从守恒和累计质量回放计算，不读取局部JuMP行。
function r3_physical_merit(c, v)
    d, h=c.data, c.data["heat"]
    scales=r3_physical_scales(c)
    rows=NamedTuple[]
    add(id, entity, t, residual, scale, unit) =
        push!(rows, (; id, entity, t, residual, scale, unit))
    V(key, i, t) = v[key][i][t]
    for (j, n) in enumerate(h["nodes"]), t in 1:d["T"]
        if n["role"]!="transit"
            r=V("H_port", j, t)-h["cp_J_kgK"]/1e6*V("m_port", j, t)*(
                V("tau_S_port", j, t)-V("tau_R_port", j, t)
            )
            add("3-17", string(j), t, r, scales.heat, "MW")
        end
        for side in ("S", "R")
            incoming=[
                (V("m_pipe", p, t), V("tau_"*side*"_out", p, t)) for
                (p, pipe) in enumerate(h["pipes"]) if pipe[side=="S" ? "to" : "from"]==j
            ]
            (side=="S" && n["role"]=="source" || side=="R" && n["role"]=="load") &&
                push!(incoming, (V("m_port", j, t), V("tau_"*side*"_port", j, t)))
            r=V("tau_"*side*"_mix", j, t)-sum(m*T for (m, T) in incoming)/sum(first, incoming)
            add(side=="S" ? "3-35" : "3-36", side*string(j), t, r, scales.temperature, "K")
        end
    end
    for p in eachindex(h["pipes"]), t in 1:d["T"], side in ("S", "R")
        replay=r3_mass_replay(c, v, p, t, side)
        star=V("tau_"*side*"_star", p, t)
        add("3-33", side*string(p), t, star-replay.star, scales.temperature, "K")
        add(
            "3-34",
            side*string(p),
            t,
            V("tau_"*side*"_out", p, t)-(
                d["ambient_K"][t]+(star-d["ambient_K"][t])*replay.attenuation
            ),
            scales.temperature,
            "K",
        )
    end
    for (p, e) in enumerate(d["electric"]["edges"]), t in 1:d["T"]
        g=V("v", e["from"], t)*V("ell", p, t)-V("P_branch", p, t)^2-V("Q_branch", p, t)^2
        add("R3-electric-equality", string(p), t, g, scales.electric[p], "pu")
    end
    return (; value = sum(abs(r.residual)/r.scale for r in rows), rows)
end

"""
    build_r3_physical_step(case, center; radius=0.1, operation=nothing, optimizer=nothing)

构建项目局部物理恢复SOCP（R3-V3-1）。热耦合和电网原支路等式作一阶展开并加入
可追踪双向弹性量；设备、负荷、模式、边界、质量守恒及原有锥保持硬约束。
目标是输入尺度归一化违反之和加0.01倍归一化步长平方，费用独立报告。
返回局部问题而不求解、不写文件；恢复中间点不代表原模型可行，不调用全变量非凸修正。
"""
function build_r3_physical_step(
    c::R2Case,
    center;
    radius = 0.1,
    operation = nothing,
    optimizer = nothing,
)
    b=build_r3_local_step(c, center; radius, operation, optimizer)
    model, v=b.model, b.variables
    old=center["values"]
    m=r2_flow_matrix(c, old["m_pipe"])
    scales=r3_physical_scales(c)
    thermal=r3_thermal_rows(c, b, m)
    rows=NamedTuple[]
    for r in thermal
        scale=r.unit=="MW" ? scales.heat : scales.temperature
        push!(rows, (; r..., scale))
    end
    V(key, i, t) = old[key][i][t]
    for (p, e) in enumerate(c.data["electric"]["edges"]), t in 1:c.data["T"]
        i=e["from"]
        a, l, P, Q=V("v", i, t), V("ell", p, t), V("P_branch", p, t), V("Q_branch", p, t)
        # g + ∇gΔx；原锥同时保留。正负弹性只承载该等式的局部误差。
        f=a*l-P^2-Q^2+l*(v["v"][i, t]-a)+a*(v["ell"][p, t]-l)-2P*(v["P_branch"][p, t]-P)-2Q*(
            v["Q_branch"][p, t]-Q
        )
        cr=@constraint(model, f==0)
        push!(
            rows,
            (
                equation = "R3-electric-equality",
                entity = string(p),
                t,
                unit = "pu",
                conversion = 1.0,
                constraint = cr,
                scale = scales.electric[p],
            ),
        )
    end
    pos=@variable(model, [1:length(rows)], lower_bound=0)
    neg=@variable(model, [1:length(rows)], lower_bound=0)
    for (i, r) in enumerate(rows)
        set_normalized_coefficient(r.constraint, pos[i], -r.scale/r.conversion)
        set_normalized_coefficient(r.constraint, neg[i], r.scale/r.conversion)
    end
    steps=copy(b.steps)
    for key in ("v", "ell", "P_branch", "Q_branch")
        vars=v[key]
        previous=r3_matrix(old[key])
        for i in eachindex(vars)
            is_fixed(vars[i]) && continue
            span=upper_bound(vars[i])-lower_bound(vars[i])
            span>0 && isfinite(span) || continue
            z=(vars[i]-previous[i])/span
            push!(steps, z)
            @constraint(model, z<=radius)
            @constraint(model, z>=-radius)
        end
    end
    penalty=@variable(model, lower_bound=0)
    @constraint(model, [penalty+1; 2 .* steps; penalty-1] in SecondOrderCone())
    merit=sum(pos)+sum(neg)
    @objective(model, Min, merit+0.01penalty)
    return merge(
        b,
        (;
            steps,
            merit_expression = merit,
            physical_rows = rows,
            physical_positive = pos,
            physical_negative = neg,
            variant = "r3_local_physical_v1",
            objective_kind = "physical_violation",
        ),
    )
end

function r3_physical_candidate(c, center, b)
    r=deepcopy(center)
    pop!(r, "sensitivity", nothing)
    r["values"]=Dict(k=>r2_extract(value.(x)) for (k, x) in b.variables)
    m=r2_flow_matrix(c, r["values"]["m_pipe"])
    r["flow_schedule"]=r2_extract(m)
    r["flow_sha256"]=r2_flow_hash(m)
    r["fixed_flows"]=true
    for (p, e) in enumerate(c.data["heat"]["pipes"]), t in 1:c.data["T"]
        a=r["values"]["alpha_"*string(p)][t]
        fs=[t-lag>0 ? m[p, t-lag] : e["flow_history"][end+t-lag] for lag in 0:(length(a)-1)]
        w=water_mass_weights(
            fs,
            c.data["heat"]["rho_kg_m3"]*e["area_m2"]*e["length_m"],
            3600c.data["dt_h"],
        )
        r["values"]["alpha_"*string(p)][t]=w.α
        r["values"]["beta_"*string(p)][t]=w.β
    end
    # κ只降低到其理论下界；所有压力约束在候选验证中重新检查。
    for side in ("S", "R"), (p, e) in enumerate(c.data["heat"]["pipes"]), t in 1:c.data["T"]
        r["values"]["kappa_"*side][p][t]=e["mu_kPa_s2_kg2"]*m[p, t]^2
    end
    r["transformation"]="local_candidate_kappa_equal_mu_m2"
    r["objective_kind"]="physical_violation"
    r["variant"]="r3_local_physical_v1"
    r["status"]="restoration_candidate"
    r["operating_cost"]=r3_operating_cost(c, r["values"])
    r["objective"]=r["operating_cost"]
    r["solver_objective"]=objective_value(b.model)
    r["termination"]=string(termination_status(b.model))
    r["primal"]=string(primal_status(b.model))
    r["local_optimality_certified"]=termination_status(b.model)==MOI.OPTIMAL
    r["physical_merit"]=r3_physical_merit(c, r["values"]).value
    for key in (
        "bound",
        "relative_gap",
        "objective_bound",
        "gap",
        "dual_objective",
        "model_pass",
        "physics_pass",
        "solver_bound",
        "raw_solver_bound",
        "solver_relative_gap",
        "bound_objective_kind",
        "bound_error",
        "dual_bound_error",
    )
        pop!(r, key, nothing)
    end
    return r
end

function r3_restore_physical(c, center, optimizer; operation, deadline)
    current=deepcopy(center)
    trace=Dict{String,Any}[]
    radius=0.1
    isnothing(optimizer) && return (; candidate = current, trace, status = "not_run_solver")
    for k in 1:20
        r3_clock()<deadline || return (; candidate = current, trace, status = "budget_exhausted")
        before=r3_physical_merit(c, current["values"]).value
        accepted=false
        for attempt in 1:12
            radius>=1e-6 && r3_clock()<deadline || break
            b=build_r3_physical_step(c, current; radius, operation)
            row=Dict{String,Any}(
                "update"=>k,
                "attempt"=>attempt,
                "radius"=>radius,
                "center"=>current,
                "before"=>before,
                "accepted"=>false,
                "switches"=>b.partials.switches,
            )
            push!(trace, row)
            if !isempty(b.partials.switches)
                row["reason"]="nonsmooth_requires_neighbor"
                # 不在切换处使用任意一侧导数；真实守恒邻段由原子问题核查。
                _, _, width=r3_flow_box(c, operation)
                for eps in (1e-4, 1e-5, 1e-6), sign in (1, -1)
                    r3_clock()<deadline || break
                    m=r3_matrix(current["values"]["m_pipe"])
                    p=r3_project(c, m+sign*eps*width, optimizer; deadline, operation)
                    p["status"]=="projected" || continue
                    q=r3_solve(
                        c,
                        ()->build_r3_subproblem(c, p["flow"]; operation),
                        optimizer;
                        deadline,
                    )
                    validate_r3_solution(c, q).model_pass || continue
                    q=reconstruct_r3_pressure(c, q)
                    after=r3_physical_merit(c, q["values"]).value
                    if after<before-1e-12
                        merge!(
                            row,
                            Dict(
                                "accepted"=>true,
                                "kind"=>"true_neighbor",
                                "epsilon"=>eps,
                                "projection"=>p,
                                "candidate"=>q,
                                "after"=>after,
                            ),
                        )
                        current=q
                        accepted=true
                        break
                    end
                end
                break
            end
            try
                set_optimizer(b.model, optimizer)
                set_silent(b.model)
                if occursin("Clarabel", solver_name(b.model))
                    for key in ("tol_gap_abs", "tol_gap_rel", "tol_feas")
                        set_optimizer_attribute(b.model, key, 1e-9)
                    end
                end
                remaining=min(60.0, deadline-r3_clock())
                remaining>0 || break
                set_time_limit_sec(b.model, remaining)
                optimize!(b.model)
            catch err
                message=sprint(showerror, err)
                reason=occursin("license", lowercase(message)) ? "not_run_license" :
                       err isa Union{MOI.UnsupportedConstraint,MOI.UnsupportedAttribute} ?
                       "unsupported_solver" : nothing
                isnothing(reason) && rethrow()
                row["reason"]=reason
                row["error"]=message
                return (; candidate = current, trace, status = reason)
            end
            row["termination"]=string(termination_status(b.model))
            if has_values(b.model)
                row["primal_violations"]=[
                    Dict("constraint"=>string(cr), "violation"=>z) for
                    (cr, z) in primal_feasibility_report(b.model; atol = 1e-6)
                ]
            end
            # 恢复只需要局部原始可行方向，不读取这些乘子生成梯度或驻点结论。
            # ALMOST_OPTIMAL/TIME_LIMIT仍必须通过同一原始约束门槛和真实物理改善检查。
            row["local_optimality_certified"]=termination_status(b.model)==MOI.OPTIMAL
            if !(
                   termination_status(b.model) in (MOI.OPTIMAL, MOI.ALMOST_OPTIMAL, MOI.TIME_LIMIT)
               ) ||
               !has_values(b.model) ||
               !isempty(primal_feasibility_report(b.model; atol = 1e-6))
                row["reason"]="local_primal_unresolved"
                radius/=2
                continue
            end
            candidate=r3_physical_candidate(c, current, b)
            predicted=value(b.merit_expression)
            after=candidate["physical_merit"]
            prediction=before-predicted
            ratio=prediction>1e-12 ? (before-after)/prediction : -Inf
            merge!(
                row,
                Dict(
                    "kind"=>"physical_local",
                    "candidate"=>candidate,
                    "predicted"=>predicted,
                    "after"=>after,
                    "ratio"=>ratio,
                    "linear_values"=>value.(all_variables(b.model)),
                ),
            )
            if prediction>1e-12 && ratio>=0.1 && after<before
                row["accepted"]=true
                current=candidate
                accepted=true
                ratio>=0.75 && (radius=min(0.2, 2radius))
                break
            end
            row["reason"]="true_physics_rejected"
            radius/=2
        end
        validate_r3_solution(c, current).physical_pass &&
            return (; candidate = current, trace, status = "physical_A1_pass")
        accepted || return (; candidate = current, trace, status = "restoration_stalled")
    end
    return (; candidate = current, trace, status = "restoration_update_limit")
end
