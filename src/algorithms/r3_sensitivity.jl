"""
    r3_transport_jacobian(flows, mass_kg, dt_s; loss_rate=0.0)

式3-27至3-34的分段解析导数。flows按当前到历史排列，单位kg/s；水质量kg，步长s，
loss_rate为损耗指数中的1/s系数。Jacobian的列对应各输入流量，返回α、β、质量权重、
停留时间、衰减及其导数。累计质量恰好命中管存量时标记switching，不声称普通可微。
调用者只取决策时段列；历史列不会成为优化变量。此函数不求解、不写文件。
"""
function r3_transport_jacobian(flows, mass_kg, dt_s; loss_rate = 0.0)
    w = water_mass_weights(flows, mass_kg, dt_s)
    isfinite(loss_rate) && loss_rate >= 0 || throw(ArgumentError("损耗率须非负有限"))
    n = length(flows)
    switching = false
    switch_starts = Int[]
    function differentiate(weights, start)
        J = zeros(n, n)
        cumulative = 0.0
        for i in start:n
            cumulative += flows[i]*dt_s
            if abs(cumulative-mass_kg) <= 1e-9*max(1, mass_kg)
                switching = true
                push!(switch_starts, start)
            end
            if 0 < weights[i] < 1
                # 部分覆盖段 a_i=(M/dt-Σ前序m)/m_i；饱和段导数为零。
                J[i, start:(i-1)] .= -1/flows[i]
                J[i, i] = -weights[i]/flows[i]
            end
        end
        return J
    end
    Ja, Jb = differentiate(w.α, 1), differentiate(w.β, 2)
    Jq = (Jb-Ja) .* reshape(flows, :, 1)
    for i in 1:n
        Jq[i, i] += w.β[i]-w.α[i]
    end
    Jw = Jq/flows[1]
    Jw[:, 1] .-= w.w/flows[1]
    residence = dt_s/2*(sum(w.α)+sum(w.β[2:end]))
    Jr = dt_s/2*vec(sum(Ja; dims = 1)+sum(Jb[2:end, :]; dims = 1))
    decay = exp(-loss_rate*residence)
    return (;
        w...,
        Ja,
        Jb,
        Jq,
        Jw,
        residence,
        Jr,
        decay,
        Jdecay = -loss_rate*decay*Jr,
        switching,
        switch_starts,
    )
end

# MOI最小化约定 L=c-y'F；包括变量界/固定等式，不能只遍历公式表。
function r3_kkt(model)
    dual_status(model) == MOI.FEASIBLE_POINT ||
        return Dict{String,Any}("trusted"=>false, "reason"=>"dual_unavailable")
    vars = all_variables(model)
    station = Dict(v=>coefficient(objective_function(model), v) for v in vars)
    denom = Dict(v=>1+abs(station[v]) for v in vars)
    rows = Dict{String,Any}[]
    primal, dualerr, complement = 0.0, 0.0, 0.0
    nrm(x) = sqrt(sum(abs2, x))
    socerr(x) = max(0.0, nrm(x[2:end])-x[1])
    for (F, S) in list_of_constraint_types(model), cr in all_constraints(model, F, S)
        obj = constraint_object(cr)
        f, set = obj.func, obj.set
        # 从原始JuMP表达式和变量值重算；后端桥接的ConstraintPrimal可能采用移位坐标。
        val, y = f isa AbstractVector ? value.(f) : value(f), dual(cr)
        fs = f isa AbstractVector ? f : [f]
        ys = y isa AbstractVector ? y : [y]
        for (a, yi) in zip(fs, ys)
            pairs = a isa VariableRef ? [(1.0, a)] : linear_terms(a)
            for (coef, v) in pairs
                station[v] -= yi*coef
                denom[v] += abs(yi*coef)
            end
        end
        if set isa MOI.EqualTo
            slack = val-set.value
            pe, de = abs(slack), 0.0
        elseif set isa MOI.GreaterThan
            slack = val-set.lower
            pe, de = max(0.0, -slack), max(0.0, -y)
        elseif set isa MOI.LessThan
            slack = val-set.upper
            pe, de = max(0.0, slack), max(0.0, y)
        elseif set isa MOI.SecondOrderCone
            slack = val
            pe, de = socerr(val), socerr(y)
        else
            return Dict{String,Any}(
                "trusted"=>false,
                "reason"=>"unsupported_kkt_set_$(typeof(set))",
            )
        end
        vals = val isa AbstractVector ? val : [val]
        ss = slack isa AbstractVector ? slack : [slack]
        pe /= max(1, nrm(vals), nrm(ss))
        de /= max(1, nrm(ys))
        ce = abs(sum(ss .* ys))/max(1, nrm(ss)*nrm(ys))
        primal, dualerr, complement = max(primal, pe), max(dualerr, de), max(complement, ce)
        push!(
            rows,
            Dict(
                "constraint"=>string(index(cr)),
                "set"=>string(typeof(set)),
                "primal"=>collect(vals),
                "raw_dual"=>collect(ys),
                "lagrange_multiplier"=>-collect(ys),
                "primal_error"=>pe,
                "dual_error"=>de,
                "complementarity"=>ce,
                "active"=>set isa MOI.SecondOrderCone ?
                          abs(val[1]-nrm(val[2:end]))<=1e-7*max(1, nrm(val)) :
                          nrm(ss)<=1e-7*max(1, nrm(vals)),
            ),
        )
    end
    st = maximum(abs(station[v])/denom[v] for v in vars; init = 0.0)
    gap =
        abs(objective_value(model)-dual_objective_value(model))/max(1, abs(objective_value(model)))
    trusted =
        termination_status(model) == MOI.OPTIMAL &&
        max(primal, dualerr, complement, st) <= 1e-6 &&
        gap <= 1e-4
    return Dict{String,Any}(
        "trusted"=>trusted,
        "reason"=>trusted ? "checked" : "kkt_failed",
        "primal"=>primal,
        "dual"=>dualerr,
        "complementarity"=>complement,
        "stationarity"=>st,
        "relative_gap"=>gap,
        "rows"=>rows,
        "active_signature"=>bytes2hex(
            sha256(join([r["constraint"] for r in rows if r["active"]], ";")),
        ),
    )
end

"""
    r3_value_sensitivity(case, built_subproblem)

在已求解的连续凸固定流量SP/弹性SP上计算式3-61采用解释。返回kg/s流量梯度、逐式贡献、
原始对偶/KKT证据和WMM分段标志。固定变量RHS贡献与热系数贡献各计一次；
弹性混合/输运行包含流量相关松弛系数的导数。只在trusted=true时可用于光滑梯度更新。
非凸物理子问题、无对偶或未通过KKT检查返回不可信状态，不伪造梯度。
"""
function r3_value_sensitivity(c::R2Case, b)
    b.class == "SOCP" && b.fixed_flows ||
        return Dict{String,Any}("trusted"=>false, "reason"=>"requires_continuous_fixed_socp")
    kkt = r3_kkt(b.model)
    kkt["trusted"] || return merge(kkt, Dict("kkt"=>deepcopy(kkt)))
    d, h, v, cs, m = c.data, c.data["heat"], b.variables, b.constraints, b.flow_schedule
    E, T = size(m)
    parts = Dict(k=>zeros(E, T) for k in ("fixed_rhs", "heat", "mixing", "transport", "loss"))
    rows = Dict{String,Any}[]
    function addpart(key, id, cr, derivative)
        contribution = -dual(cr) .* derivative
        parts[key] .+= contribution
        push!(
            rows,
            Dict("equation"=>id, "raw_dual"=>dual(cr), "gradient"=>r2_extract(contribution)),
        )
    end
    for p in 1:E, t in 1:T
        parts["fixed_rhs"][p, t] = dual(FixRef(v["m_pipe"][p, t]))
    end
    # 端口质量守恒给出的线性映射，不对温度最优解求导。
    portJ = zeros(length(h["nodes"]), E)
    for (j, node) in enumerate(h["nodes"]), (p, pipe) in enumerate(h["pipes"])
        sign = node["role"] == "source" ? 1 : node["role"] == "load" ? -1 : 0
        portJ[j, p] = sign*(Int(pipe["from"]==j)-Int(pipe["to"]==j))
    end
    active = findall(n->n["role"]!="transit", h["nodes"])
    for (k, j) in enumerate(active), t in 1:T
        D = zeros(E, T)
        D[:, t] .= -portJ[j, :]*(value(v["tau_S_port"][j, t])-value(v["tau_R_port"][j, t]))
        addpart("heat", "3-17", cs["3-17"][2((k-1)*T+t)-1], D)
    end
    function slackdelta(id, entity, t)
        i = findfirst(r->r.equation==id && r.entity==entity && r.t==t, b.elastic_rows)
        isnothing(i) && return 0.0
        return b.elastic_rows[i].scale*(
            value(v["elastic_positive"][i])-value(v["elastic_negative"][i])
        )
    end
    for side in ("S", "R"), j in eachindex(h["nodes"]), t in 1:T
        edges, local_in = r2_inflows(d, side, j)
        length(edges)+Int(local_in)>1 || continue
        id = side=="S" ? "3-35" : "3-36"
        D = zeros(E, T)
        mix = value(v["tau_"*side*"_mix"][j, t])
        s = slackdelta(id, side*string(j), t)
        for p in edges
            D[p, t] += mix-value(v["tau_"*side*"_out"][p, t])-s
        end
        if local_in
            D[:, t] .+= portJ[j, :]*(mix-value(v["tau_"*side*"_port"][j, t])-s)
        end
        addpart("mixing", id, cs[id][(j-1)*T+t], D)
    end
    switches = String[]
    for (p, pipe) in enumerate(h["pipes"]), t in 1:T
        dt = 3600*d["dt_h"]
        mass = h["rho_kg_m3"]*pipe["area_m2"]*pipe["length_m"]
        Td = ceil(Int, mass/(dt*pipe["flow_min"]))+1
        fs = [t-s>0 ? m[p, t-s] : pipe["flow_history"][end+t-s] for s in 0:Td]
        J = r3_transport_jacobian(
            fs,
            mass,
            dt;
            loss_rate = pipe["epsilon_W_mK"]/(h["cp_J_kgK"]*h["rho_kg_m3"]*pipe["area_m2"]),
        )
        any(start<=t for start in J.switch_starts) && push!(switches, "$p:$t")
        for (k, side) in enumerate(("S", "R"))
            idx = 2((p-1)*T+t-1)+k
            temps = [
                t-s>0 ? value(v["tau_"*side*"_in"][p, t-s]) : pipe[side*"_history_K"][end+t-s]
                for s in 0:Td
            ]
            star = value(v["tau_"*side*"_star"][p, t])
            D, L = zeros(E, T), zeros(E, T)
            for lag in 0:min(Td, t-1)
                D[p, t-lag] = -sum(J.Jq[:, lag+1] .* temps)
                lag==0 && (D[p, t] += star-slackdelta("3-33", side*string(p), t))
                L[p, t-lag] = -(star-d["ambient_K"][t])*J.Jdecay[lag+1]
            end
            addpart("transport", "3-33", cs["3-33"][idx], D)
            addpart("loss", "3-34", cs["3-34"][idx], L)
        end
    end
    gradient = reduce(+, values(parts))
    return Dict{String,Any}(
        "trusted"=>true,
        "reason"=>"checked",
        "kkt"=>kkt,
        "gradient"=>r2_extract(gradient),
        "parts"=>Dict(k=>r2_extract(x) for (k, x) in parts),
        "rows"=>rows,
        "switches"=>switches,
        "smooth"=>isempty(switches),
        "objective_kind"=>b.objective_kind,
    )
end
