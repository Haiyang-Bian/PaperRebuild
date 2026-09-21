const R7_ADVERSARY_VERIFY_FILE = @__FILE__

"""
    validate_r7_dual(lp, fault, lambda)

从规范行和保存的乘子独立重算符号、完整平稳性及对偶目标。沿用A1的1e-6绝对/相对门槛，
不修改乘子或给出缺失的最优性证书；本检查只证明所保存对偶的数值可行性。
固定故障原始恢复还须由独立物理验证器检查，且需有效界才能认证最优值。
"""
function validate_r7_dual(lp::R7RecourseLP, gamma, lambda)
    r7_lp_assert(lp)
    d=lp.data
    length(lambda)==length(d["rows"]) && all(isfinite, lambda) || error("对偶形状或有限性错误")
    length(gamma)==length(d["fault_names"]) && all(x->x in (0, 1), gamma) || error("故障错误")
    lhs=zeros(length(d["cost"]))
    magnitude=zeros(length(lhs))
    objective=Float64(d["constant"])
    rows=Dict{String,Any}[]
    function check(id, residual, scale)
        tolerance=1e-6*(1+max(1.0, scale))
        push!(
            rows,
            Dict(
                "id"=>id,
                "residual"=>Float64(residual),
                "tolerance"=>tolerance,
                "pass"=>isfinite(residual)&&residual<=tolerance,
            ),
        )
    end
    for (i, row) in enumerate(d["rows"])
        check("lambda_nonpositive_$i", max(0.0, lambda[i]), abs(lambda[i]))
        for (j, a) in zip(row["columns"], row["coefficients"])
            lhs[j]+=a*lambda[i]
            magnitude[j]+=abs(a*lambda[i])
        end
        rhs=row["rhs"]+sum(
            (a*gamma[j] for (j, a) in zip(row["fault_columns"], row["fault_coefficients"]));
            init = 0.0,
        )
        objective+=rhs*lambda[i]
    end
    for j in eachindex(lhs)
        check(
            "stationarity_"*d["variable_names"][j],
            abs(lhs[j]-d["cost"][j]),
            max(magnitude[j], abs(d["cost"][j])),
        )
    end
    Dict(
        "dual_feasible"=>all(row["pass"] for row in rows),
        "dual_objective_MWh"=>objective,
        "matrix_sha256"=>lp.sha256,
        "rows"=>rows,
    )
end

function r7_validate_adversary_values(c, topologies, values)
    gamma=values["fault"]
    r7_check_fault(c, gamma)
    raw=values["fault_raw"]
    length(raw)==length(gamma) && all(isfinite, raw) && all(abs.(raw .- gamma) .<= 1e-6) ||
        error("保存故障不是二值求解原值")
    theta=values["theta_MWh"]
    isfinite(theta) || error("对手候选非有限")
    caps=r7_recovery_loss_cap(c)
    tol=1e-6*(1+max(1.0, caps.cap_MWh))
    valid=-tol<=theta<=caps.cap_MWh+tol
    length(values["blocks"])==length(topologies) || error("对手模式原值缺失")
    checks=Dict{String,Any}[]
    for (z, block) in zip(topologies, values["blocks"])
        lp=r7_recovery_lp(c, z)
        lp.sha256==block["matrix_sha256"] || error("对手LP系数身份改变")
        dual=validate_r7_dual(lp, gamma, block["lambda"])
        expected=[(i, j) for (i, row) in enumerate(lp.data["rows"]) for j in row["fault_columns"]]
        length(block["products"])==length(expected) || error("指示乘积原值缺失")
        products_pass=true
        for (p, (i, j)) in zip(block["products"], expected)
            p["row"]==i && p["fault_column"]==j || error("指示乘积行身份改变")
            target=gamma[j]*block["lambda"][i]
            residual=abs(p["value"]-target)
            products_pass &= isfinite(residual) && residual<=1e-6*(1+max(1.0, abs(target)))
        end
        bound_pass=theta<=dual["dual_objective_MWh"]+tol
        valid &= dual["dual_feasible"]&&products_pass&&bound_pass
        push!(checks, Dict("dual"=>dual, "products_pass"=>products_pass, "bound_pass"=>bound_pass))
    end
    Dict("model_pass"=>valid, "blocks"=>checks, "cap_MWh"=>caps.cap_MWh)
end

"""
    validate_r7_adversary(case, result)

只读重建各恢复拓扑的LP行，核查原始对偶、指示乘积、完整恢复物理值和拓扑生成顺序。
分别重算最坏失供下界、未截断上界及安全门槛；截断饱和保持上界无限，
不把对手可行值当成完整恢复损失。求解器认证界保留其来源，不伪称解析证明。
"""
function validate_r7_adversary(c::R7RecoveryCase, r)
    r7_recovery_assert(c)
    r["schema"]=="r7-adversary-result-v1" &&
    r["version"]=="r7_inner_indicator_v1" &&
    r["case_sha256"]==c.sha256 &&
    r["preplan_id"]==c.data["preplan_id"] &&
    r["objective_kind"]==r7_loss_objective_kind(c.data; worst = true) &&
    r["preplan_optimality_verified"]===false &&
    r["author_literal_algorithm"]===false || error("内层对手身份或范围错误")
    cap=r7_recovery_loss_cap(c).cap_MWh
    cap_tol=1e-6*(1+max(1.0, cap))
    zs=Vector{Int}[]
    checks=Dict{String,Any}[]
    lower, upper=0.0, Inf
    worst_fault=Int[]
    inf_certificate=false
    for (k, it) in enumerate(r["iterations"])
        master=it["master"]
        master["topologies"]==zs || error("恢复拓扑池不是此前认证模式")
        master["objective_kind"]=="capped_restricted_worst_loss_MWh" || error("主问题目标混淆")
        ck=Dict{String,Any}("adversary_pass"=>false, "recovery_pass"=>false)
        if haskey(master, "values")
            q=r7_validate_adversary_values(c, zs, master["values"])
            isequal(q, master["validation"]) || error("对手原值与摘要不同")
            ck["adversary_pass"]=q["model_pass"]
            if q["model_pass"] && haskey(master, "solver_upper_bound_MWh")
                master["termination_status"] in
                ("OPTIMAL", "TIME_LIMIT", "NODE_LIMIT", "ITERATION_LIMIT", "SOLUTION_LIMIT") ||
                    error("无效终止状态不能提供对手上界")
                b=master["solver_upper_bound_MWh"]
                isfinite(b) && b>=master["values"]["theta_MWh"]-cap_tol ||
                    error("对手最大化上界与候选矛盾")
                # R7-I3：只有未饱和截断值才是完整最坏失供的有限上界。
                ck["cap_saturated"]=b>=cap-cap_tol
                b<cap-cap_tol && (upper=min(upper, b))
            end
        end
        if haskey(it, "recovery")
            ck["adversary_pass"] || error("不合格对手候选不可进入恢复检查")
            rec=it["recovery"]
            rec["fault"]==master["values"]["fault"] || error("恢复检查故障与对手不同")
            q=validate_r7_recovery(c, rec)
            isequal(q, rec["validation"]) && q["model_pass"]==rec["candidate_accepted"] ||
                error("恢复原值/摘要不同")
            ck["recovery_pass"]=q["model_pass"]
            rec["status"]=="infeasible_certified" &&
                get(rec, "termination_status", "")!="INFEASIBLE" &&
                error("不可行标签缺少对应求解器状态")
            lb=rec["status"]=="infeasible_certified" ? Inf : get(rec, "lower_bound_MWh", 0.0)
            isnan(lb) && error("恢复下界非数")
            q["model_pass"] &&
                lb>q["loss_MWh"]+1e-6*(1+max(1, abs(q["loss_MWh"]))) &&
                error("恢复上下界冲突")
            if lb>lower || isempty(worst_fault)
                lower=max(lower, lb)
                worst_fault=rec["fault"]
            end
            inf_certificate |= rec["status"]=="infeasible_certified"
            if q["model_pass"]
                z=round.(Int, vec(r7_unpack(rec["values"], "z")))
                r7_topology_roots(c, rec["fault"], z)===nothing && error("恢复模式不是合格森林")
                if !(z in zs)
                    get(it, "added_topology", Int[])==z || error("合格新拓扑未登记")
                    push!(zs, z)
                else
                    haskey(it, "added_topology") && error("重复拓扑不能称新模式")
                end
            elseif haskey(it, "added_topology")
                error("不可行/未知恢复不能添加拓扑")
            end
        elseif haskey(it, "added_topology")
            error("缺少完整恢复来源")
        end
        if isfinite(upper) && lower>upper+1e-6*(1+max(1.0, abs(upper)))
            error("内层最坏失供上下界矛盾")
        end
        ck["lower_bound_MWh"]=lower
        ck["upper_bound_MWh"]=upper
        push!(checks, ck)
    end
    limit=c.data["loss_limit_MWh"]
    tol=1e-6*(1+max(1.0, limit))
    status=upper<=limit+tol ? "safe_adopted_model" :
           lower>limit+tol ? "violation_certified" : "unresolved"
    gap=isfinite(lower)&&isfinite(upper) ? (upper-lower)/max(1.0, abs(upper)) : Inf
    length(r["iterations"])<=r["max_iterations"] || error("内层超过声明轮数")
    r["status"]=="infeasible_recovery_certified" &&
        !inf_certificate &&
        error("错误的不可行完成标签")
    r["status"]=="worst_loss_certified" && !(-1e-6<=gap<=1e-4) && error("错误的最坏值完成标签")
    r["status"]=="threshold_counterexample_certified" &&
        status!="violation_certified" &&
        error("缺少门槛反例")
    Dict(
        "lower_bound_MWh"=>lower,
        "upper_bound_MWh"=>upper,
        "relative_gap"=>gap,
        "gap_certified"=>-1e-6<=gap<=1e-4,
        "threshold_status"=>status,
        "infeasible_recovery_certified"=>inf_certificate,
        "worst_fault"=>worst_fault,
        "topologies"=>zs,
        "iterations"=>checks,
        "cap_MWh"=>cap,
        "detailed_disaster_heat_verified"=>false,
        "ac_grid_verified"=>false,
    )
end
