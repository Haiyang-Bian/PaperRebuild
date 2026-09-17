# 独立累计质量回放：不调用建模器或water_mass_weights。
function r3_mass_replay(c, v, p, t, side)
    d, h = c.data, c.data["heat"]
    pipe = h["pipes"][p]
    flows = reverse(vcat(pipe["flow_history"], v["m_pipe"][p][1:t]))
    temperatures = reverse(vcat(pipe[side*"_history_K"], v["tau_"*side*"_in"][p][1:t]))
    q = flows .* (3600d["dt_h"])
    M = h["rho_kg_m3"]*pipe["area_m2"]*pipe["length_m"]
    sum(q[2:end]) >= M-1e-9*max(1, M) || throw(ArgumentError("独立回放历史不足"))
    cumulative = cumsum(q)
    alpha = [clamp((M-(cumulative[i]-q[i]))/q[i], 0, 1) for i in eachindex(q)]
    beta = [i==1 ? 1.0 : clamp((M-(cumulative[i]-q[i]-q[1]))/q[i], 0, 1) for i in eachindex(q)]
    w = (beta-alpha) .* q ./ q[1]
    star = sum(w .* temperatures)
    residence = d["dt_h"]*3600*(sum(alpha)+sum(beta[2:end]))/2
    attenuation =
        exp(-pipe["epsilon_W_mK"]*residence/(h["rho_kg_m3"]*h["cp_J_kgK"]*pipe["area_m2"]))
    out = d["ambient_K"][t]+(star-d["ambient_K"][t])*attenuation
    return (; star, out, attenuation, residence, weights = w)
end

"""
    validate_r3_solution(case, result)

对一个阶段或完整R3运行独立核查成本、实际流量、诊断松弛、修正距离与物理残差。
热输运额外使用独立累计质量回放，不调用JuMP表达式；A1沿用原门槛。
诊断可通过自身约束但physical_pass始终为false。完整运行只接受已重新验证的最终阶段，
不是读取保存的绿色标志。旧R2初始化结果仍按原验证器检查。
"""
function validate_r3_solution(c::R2Case, result)
    if get(result, "schema", "")=="r3-run-v1"
        result["input_sha256"]==c.sha256 || throw(ArgumentError("R3运行与输入哈希不同"))
        reports = [validate_r3_solution(c, r) for r in result["stages"]]
        i = result["final_stage"]
        0<=i<=length(reports) || throw(ArgumentError("最终阶段索引非法"))
        valid =
            i>0 &&
            reports[i].physical_pass &&
            haskey(result["stages"][i], "variant") &&
            get(result["stages"][i], "objective_kind", "")!="normalized_slack"
        if haskey(result, "initial_flow")
            m = r2_flow_matrix(c, result["initial_flow"])
            r2_flow_hash(m)==result["initial_flow_sha256"] ||
                throw(ArgumentError("初始流量哈希不一致"))
        end
        if haskey(result, "iterations")
            all(
                validate_r3_iteration(c, row; stages = result["stages"]).pass for
                row in result["iterations"]
            ) || throw(ArgumentError("外层迭代证据不一致"))
            for k in 2:length(result["iterations"])
                previous=result["iterations"][k-1]
                previous["accepted"] &&
                maximum(
                    abs,
                    r3_matrix(previous["accepted_flow"])-r3_matrix(result["iterations"][k]["flow"]),
                )<=1e-6 || throw(ArgumentError("外层流量链断裂"))
            end
        end
        return (
            status = valid ? "checked_relations_pass" : result["status"],
            model_pass = valid,
            physical_pass = valid,
            rows = i>0 ? reports[i].rows : NamedTuple[],
            stages = reports,
        )
    end
    base = validate_r2_solution(c, result)
    haskey(result, "values") ||
        return (status = base.status, model_pass = false, physical_pass = false, rows = base.rows)
    !haskey(result, "variant") && return (
        status = base.status,
        model_pass = base.model_pass,
        physical_pass = base.original_physics_pass,
        rows = base.rows,
    )
    kind = result["objective_kind"]
    diagnostic = kind=="normalized_slack"
    rows = NamedTuple[]
    for row in base.rows
        relaxed = diagnostic && row.equation in ("3-17", "3-35:36", "3-33:34")
        push!(rows, relaxed ? merge(row, (scope = "relaxed",)) : row)
    end
    function record(id, entity, t, value, unit, tol; scope = "model")
        residual = abs(Float64(value))
        push!(
            rows,
            (
                equation = id,
                scope,
                entity = string(entity),
                t,
                residual,
                unit,
                tolerance = tol,
                pass = isfinite(residual)&&residual<=tol,
            ),
        )
    end
    d, h, v = c.data, c.data["heat"], result["values"]
    V(key, i, t) = v[key][i][t]
    if haskey(result, "flow_sha256")
        scheduled = result[result["fixed_flows"] ? "flow_schedule" : "initial_flow"]
        r2_flow_hash(r2_flow_matrix(c, scheduled))==result["flow_sha256"] ||
            throw(ArgumentError("阶段流量哈希不一致"))
    end
    record(
        "R3-cost-field",
        0,
        0,
        result["operating_cost"]-result["objective"],
        "currency",
        1e-6*max(1, abs(result["objective"])),
    )
    for (p, pipe) in enumerate(h["pipes"]), t in 1:d["T"], side in ("S", "R")
        replay = r3_mass_replay(c, v, p, t, side)
        record(
            "R3-mass-replay",
            side*string(p),
            t,
            V("tau_"*side*"_out", p, t)-replay.out,
            "K",
            1e-4;
            scope = "physics",
        )
        lo, hi = h[side*"_bounds_K"]
        record(
            "R3-star-bounds",
            side*string(p),
            t,
            max(0, lo-V("tau_"*side*"_star", p, t), V("tau_"*side*"_star", p, t)-hi),
            "K",
            1e-4,
        )
    end
    if diagnostic
        total = 0.0
        for (i, row) in enumerate(result["elastic_rows"])
            id, t, entity = row["equation"], row["t"], row["entity"]
            pos, neg = v["elastic_positive"][i], v["elastic_negative"][i]
            total += pos+neg
            record("R3-slack-bound", i, t, max(0, -pos, -neg), "1", 1e-8)
            if id=="3-17"
                j = parse(Int, entity)
                residual =
                    V("H_port", j, t)-h["cp_J_kgK"]/1e6*V("m_port", j, t)*(
                        V("tau_S_port", j, t)-V("tau_R_port", j, t)
                    )
            else
                side, j = entity[1:1], parse(Int, entity[2:end])
                if id in ("3-35", "3-36")
                    # 根据端点独立确定真正入流，供/回方向相反。
                    incoming = [
                        (V("m_pipe", p, t), V("tau_"*side*"_out", p, t)) for
                        (p, pipe) in enumerate(h["pipes"]) if pipe[side=="S" ? "to" : "from"]==j
                    ]
                    role = h["nodes"][j]["role"]
                    (side=="S" && role=="source" || side=="R" && role=="load") &&
                        push!(incoming, (V("m_port", j, t), V("tau_"*side*"_port", j, t)))
                    residual =
                        V("tau_"*side*"_mix", j, t)-sum(m*T for (m, T) in incoming)/sum(
                            first,
                            incoming,
                        )
                else
                    replay = r3_mass_replay(c, v, j, t, side)
                    star = V("tau_"*side*"_star", j, t)
                    residual =
                        id=="3-33" ? star-replay.star :
                        V("tau_"*side*"_out", j, t)-(
                            d["ambient_K"][t]+(star-d["ambient_K"][t])*replay.attenuation
                        )
                end
            end
            tol = row["unit"]=="MW" ? 1e-6*(1+d["electric"]["grid_max_MW"]) : 1e-4
            record("R3-elastic-"*id, entity, t, residual-row["scale"]*(pos-neg), row["unit"], tol)
        end
        record(
            "R3-objective-slack",
            0,
            0,
            total-result["solver_objective"],
            "1",
            1e-6*max(1, abs(total)),
        )
    elseif kind=="flow_distance"
        m0 = r2_flow_matrix(c, result["initial_flow"])
        i, total = 0, 0.0
        for (p, pipe) in enumerate(h["pipes"]), t in 1:d["T"]
            width = pipe["flow_max"]-pipe["flow_min"]
            width==0 && continue
            i+=1
            q = v["flow_deviation"][i]
            total += q
            record(
                "R3-distance-epigraph",
                p,
                t,
                max(0, abs(V("m_pipe", p, t)-m0[p, t])/width-q, -q),
                "1",
                1e-6,
            )
        end
        record(
            "R3-objective-distance",
            0,
            0,
            total-result["solver_objective"],
            "1",
            1e-6*max(1, abs(total)),
        )
    elseif kind=="operating_cost"
        record(
            "R3-objective-cost",
            0,
            0,
            result["solver_objective"]-result["operating_cost"],
            "currency",
            1e-6*max(1, abs(result["operating_cost"])),
        )
    else
        throw(ArgumentError("未知目标语义"))
    end
    model_pass = all(r.pass for r in rows if r.scope=="model")
    physical_pass = !diagnostic && model_pass && all(r.pass for r in rows if r.scope=="physics")
    return (
        status = physical_pass ? "checked_relations_pass" :
                 diagnostic && model_pass ? "diagnostic_only" : "relations_failed",
        model_pass,
        physical_pass,
        rows,
    )
end
