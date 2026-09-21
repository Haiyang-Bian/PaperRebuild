const R5_COMMITMENT_VERIFY_FILE=@__FILE__

"""
    validate_r5_commitment(case, result)

从保存数值逐情景重放电热物理/交付，独立汇总日前费用一次及期望补救费用。
共同承诺逐量检查有限边界与PCC容量；概率还原后的条件乘子走原独立KKT。
另以手写共同参数梯度检查一阶段驻点、界乘子、互补和整体原对偶差，不读取JuMP对象。
模型、费用、KKT和求解器有效界分别报告；不宣称样本外可靠率或完整交流/水压认证。
"""
function validate_r5_commitment(c::R5CommitmentCase, r)
    r5_commitment_assert_case(c)
    get(r, "case_sha256", nothing)==c.sha256||error("共同承诺结果输入不符")
    out=Dict{String,Any}(
        "model_pass"=>false,
        "cost_pass"=>false,
        "kkt_pass"=>false,
        "optimality_pass"=>false,
        "conditional_kkt_pass"=>false,
        "rows"=>Dict{String,Any}[],
        "scenarios"=>Dict{String,Any}(),
        "status"=>"missing_candidate",
    )
    haskey(r, "first_stage")&&haskey(r, "scenarios")||return out
    d=c.data
    base=first(d["scenarios"])["case"]
    T, dt=base["T"], base["dt_h"]
    x=r["first_stage"]
    validshape=Set(keys(x))==Set(R5_COMMITMENT_KEYS)&&all(
        k->x[k] isa AbstractVector&&length(x[k])==T&&all(v->v isa Real&&isfinite(v), x[k]),
        R5_COMMITMENT_KEYS,
    )
    validshape&&Set(keys(r["scenarios"]))==Set(s["id"] for s in d["scenarios"]) ||
        (out["status"] = "invalid_inventory"; return out)
    record(id, group, residual, tol) = push!(
        out["rows"],
        Dict(
            "id"=>id,
            "group"=>group,
            "residual"=>abs(Float64(residual)),
            "tolerance"=>tol,
            "normalized"=>abs(residual)/tol,
            "pass"=>isfinite(residual)&&abs(residual)<=tol,
        ),
    )
    ep=max(
        1.0,
        base["electric"]["pcc_max_MW"],
        sum(a["p_max_MW"] for a in base["devices"]; init = 0.0),
    )
    ptol=1e-6*(1+ep)
    # 与建模侧的一阶段行表分别实现，防止共同索引/符号错误自证。
    for k in R5_COMMITMENT_KEYS, t in 1:T
        lo, hi=d["bounds"][k]["lower"][t], d["bounds"][k]["upper"][t]
        record("$k/$t", "first_stage", max(0.0, lo-x[k][t], x[k][t]-hi), ptol)
    end
    for t in 1:T
        record(
            "PCC-up/$t",
            "first_stage",
            max(0.0, base["electric"]["pcc_min_MW"]-x["P_DA_MW"][t]+x["R_up_MW"][t]),
            ptol,
        )
        record(
            "PCC-down/$t",
            "first_stage",
            max(0.0, x["P_DA_MW"][t]+x["R_down_MW"][t]-base["electric"]["pcc_max_MW"]),
            ptol,
        )
    end
    p=d["day_ahead"]
    da=dt*sum(
        p["energy_price"][t]*x["P_DA_MW"][t]-p["up_price"][t]*x["R_up_MW"][t]-p["down_price"][t]*x["R_down_MW"][t]
        for t in 1:T
    )
    expected=da
    gradients=Dict(k=>zeros(T) for k in R5_COMMITMENT_KEYS)
    intercept=0.0
    for s in d["scenarios"]
        id=s["id"]
        view=r5_commitment_view(c, s, x)
        rr=r["scenarios"][id]
        rr["case_sha256"]==view.sha256||error("条件视图身份不一致")
        v=validate_r5_dispatch(view, rr)
        kkt=validate_r5_dispatch_duals(view, rr)
        out["scenarios"][id]=Dict{String,Any}("validation"=>v, "kkt"=>kkt)
        haskey(v, "operating_net_cost")||(out["status"] = "invalid_scenario_values"; return out)
        q=v["operating_net_cost"]-da
        out["scenarios"][id]["recourse_cost"]=q
        expected+=s["probability"]*q
        if kkt["kkt_pass"]
            sens=r5_dispatch_sensitivity(view, rr)
            out["scenarios"][id]["sensitivity"]=sens["gradient"]
            for k in R5_COMMITMENT_KEYS
                gradients[k].+=s["probability"] .* sens["gradient"][k]
            end
            intercept+=s["probability"]*(
                kkt["dual_objective"]-da -
                sum(sum(sens["gradient"][k] .* x[k]) for k in R5_COMMITMENT_KEYS)
            )
        end
    end
    record(
        "expected-objective",
        "cost",
        get(r, "solver_objective", NaN)-expected,
        1e-6*max(1, abs(expected)),
    )
    out["day_ahead_cost"], out["expected_recourse_cost"], out["expected_net_cost"]=da,
    expected-da,
    expected
    out["model_pass"]=all(z["pass"] for z in out["rows"] if z["group"]=="first_stage") && all(
        v["validation"]["model_pass"]&&v["validation"]["auxiliary_exact_pass"] for
        v in values(out["scenarios"])
    )
    out["cost_pass"]=all(z["pass"] for z in out["rows"] if z["group"]=="cost") &&
                     all(v["validation"]["cost_pass"] for v in values(out["scenarios"]))
    out["conditional_kkt_pass"]=all(v["kkt"]["kkt_pass"] for v in values(out["scenarios"]))
    raw=get(r, "weighted_raw_scenario_duals", Dict())
    scaling=Set(keys(raw))==Set(s["id"] for s in d["scenarios"])
    for s in d["scenarios"]
        rr=r["scenarios"][s["id"]]
        if all(haskey(rr, k) for k in ("raw_constraint_duals", "raw_bound_duals"))&&haskey(
            raw,
            s["id"],
        )
            unweighted=merge(rr["raw_constraint_duals"], rr["raw_bound_duals"])
            weighted=raw[s["id"]]
            scaling &=
                get(rr, "dual_probability_divisor", NaN)==s["probability"]&&Set(keys(unweighted))==Set(
                    keys(weighted),
                ) &&
                all(
                    k->weighted[k] isa Real&&isfinite(weighted[k])&&unweighted[k]==weighted[k]/s["probability"],
                    keys(unweighted),
                )
        else
            scaling=false
        end
    end
    out["dual_scaling_pass"]=scaling
    y=get(r, "raw_first_stage_duals", Dict())
    required=Set(
        vcat(
            ["$k/$t/$side" for k in R5_COMMITMENT_KEYS for t in 1:T for side in ("lower", "upper")],
            ["PCC-$dir/$t" for dir in ("up", "down") for t in 1:T],
        ),
    )
    if out["conditional_kkt_pass"]&&scaling&&Set(keys(y))==required&&all(
        v->v isa Real&&isfinite(v),
        values(y),
    )
        price=max(
            1.0,
            maximum(abs.(vcat(values(p)...))),
            maximum(s["case"]["realtime"]["penalty_USD_MWh"] for s in d["scenarios"]),
            maximum(maximum(abs.(s["case"]["realtime"]["price"])) for s in d["scenarios"]),
            maximum(a["cost_USD_MWh"] for a in base["devices"]; init = 0.0),
        )
        money=max(1.0, dt*ep*price)
        for (k, fee) in (
            ("P_DA_MW", p["energy_price"]),
            ("R_up_MW", -p["up_price"]),
            ("R_down_MW", -p["down_price"]),
        )
            gradients[k].+=dt*fee
        end
        dualobj=intercept
        for k in R5_COMMITMENT_KEYS, t in 1:T, side in ("lower", "upper")
            id="$k/$t/$side"
            b=d["bounds"][k][side][t]
            signed=side=="lower" ? max(0.0, -y[id]) : max(0.0, y[id])
            record(id*"/sign", "kkt", signed*ep/money, 1e-6)
            record(id*"/complementarity", "kkt", y[id]*(x[k][t]-b)/money, 1e-6)
            gradients[k][t]-=y[id]
            dualobj+=b*y[id]
        end
        for t in 1:T
            u, l=y["PCC-up/$t"], y["PCC-down/$t"]
            bmin, bmax=base["electric"]["pcc_min_MW"], base["electric"]["pcc_max_MW"]
            record("PCC-up/$t/sign", "kkt", max(0.0, -u)*ep/money, 1e-6)
            record("PCC-down/$t/sign", "kkt", max(0.0, l)*ep/money, 1e-6)
            record("PCC-up/$t/comp", "kkt", u*(x["P_DA_MW"][t]-x["R_up_MW"][t]-bmin)/money, 1e-6)
            record(
                "PCC-down/$t/comp",
                "kkt",
                l*(x["P_DA_MW"][t]+x["R_down_MW"][t]-bmax)/money,
                1e-6,
            )
            gradients["P_DA_MW"][t]-=u+l
            gradients["R_up_MW"][t]+=u
            gradients["R_down_MW"][t]-=l
            dualobj+=bmin*u+bmax*l
        end
        for k in R5_COMMITMENT_KEYS, t in 1:T
            record("$k/$t/stationarity", "kkt", gradients[k][t]*ep/money, 1e-6)
        end
        record(
            "global-primal-dual-gap",
            "kkt",
            (expected-dualobj)/max(1, abs(expected), abs(dualobj)),
            1e-4,
        )
        out["independent_dual_objective"]=dualobj
        out["kkt_pass"]=out["model_pass"]&&out["cost_pass"]&&all(
            z["pass"] for z in out["rows"] if z["group"]=="kkt"
        )
    end
    bound=get(r, "solver_objective_bound", NaN)
    out["valid_bound"]=isfinite(bound)&&bound<=expected+1e-6*max(1, abs(expected))
    out["relative_gap"]=out["valid_bound"] ?
                        max(0.0, expected-bound)/max(1, abs(expected), abs(bound)) : Inf
    out["optimality_pass"]=out["kkt_pass"]&&out["valid_bound"]&&out["relative_gap"]<=1e-4
    out["status"]="evaluated"
    out
end
