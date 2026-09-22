"""
    validate_r7_normal_flow(case, spec, result)

R7-F4独立核验原值流量界、质量守恒、共享信息、费用和所有正常关系。按保存流量重新做水团
裁切回放，不使用正部辅助量或JuMP表达式。数值条件案例仅用于复用原验证器，原输入身份不变；
未通过质量守恒/活动域的候选不会通过。最优性仅属于本无损正向正常控制域，不认证灾害恢复。
"""
function validate_r7_normal_flow(c, s, r)
    bd=r7_normal_flow_check(c, s)
    r["schema"]=="r7-normal-flow-result-v1" &&
    r["case_sha256"]==c.sha256 &&
    r["spec_sha256"]==r7_digest(s) &&
    r["version"]==s["version"] &&
    r["objective_kind"]=="expected_normal_cost_USD" &&
    r["full_preplan_optimality_verified"]===false || error("连续流量结果身份/范围错误")
    out=Dict{String,Any}(
        "model_pass"=>false,
        "optimality_pass"=>false,
        "full_preplan_optimality_verified"=>false,
        "detailed_recovery_verified"=>false,
        "rows"=>Dict{String,Any}[],
    )
    haskey(r, "values") || return out
    r["status"] in
    ("infeasible_certified", "budget_exhausted", "time_limit_no_solution", "license_unavailable") &&
        error("连续流量状态与原值冲突")
    Set(keys(r["flow_values"]))==Set(["pipe", "source", "load"]) || error("连续流量字段错误")
    f=Dict(k=>r7_unpack(r["flow_values"], k) for k in ("pipe", "source", "load"))
    rec(id, i, t, x, tol) = push!(
        out["rows"],
        Dict(
            "id"=>id,
            "element"=>i,
            "time"=>t,
            "unit"=>"kg/s",
            "residual"=>Float64(abs(x)),
            "tolerance"=>Float64(tol),
            "pass"=>abs(x)<=tol,
        ),
    )
    for k in keys(f)
        size(f[k])==size(bd[k*"_min"]) && all(isfinite, f[k]) || error("流量原值形状/有限性错误")
        for I in CartesianIndices(f[k])
            lo, hi=bd[k*"_min"][I], bd[k*"_max"][I]
            rec("R7-F1-$k-bound", I[1], I[2], max(0, lo-f[k][I], f[k][I]-hi), 1e-6*max(1, hi))
        end
    end
    h=c.data["heat"]
    ps=h["pipes"]
    for j in 1:h["nodes"], t in 1:c.data["periods"]
        incoming=sum(f["pipe"][a, t] for (a, p) in enumerate(ps) if p["to"]==j; init = 0.0)
        outgoing=sum(f["pipe"][a, t] for (a, p) in enumerate(ps) if p["from"]==j; init = 0.0)
        rec(
            "6-30",
            j,
            t,
            incoming+f["source"][j, t]-outgoing-f["load"][j, t],
            1e-6*max(1, incoming, outgoing, f["source"][j, t], f["load"][j, t]),
        )
    end
    # 活动端口严格正，固定闲置值允许求解器尾差但不作为混合权重：更大的不一致仍独立失败。
    # 不剪裁原值。固定为0的变量应由求解器返回精确0，否则本版本拒绝构造条件回放。
    all(>(0), f["pipe"]) || return out
    for k in ("source", "load")
        all(bd[k*"_max"][I]==0 ? f[k][I]==0 : f[k][I]>0 for I in CartesianIndices(f[k])) ||
            return out
    end
    nc=r7_normal_at_flow(c, f; check_input = false)
    nr=Dict{String,Any}(
        "schema"=>"r7-normal-result-v1",
        "version"=>"r7_normal_prescribed_v1",
        "case_sha256"=>nc.sha256,
        "objective_kind"=>"expected_normal_cost_USD",
        "thermal_model"=>nc.data["thermal_model"],
        "full_preplan_optimality_verified"=>false,
        "status"=>r["status"],
        "values"=>r["values"],
        "chp_values"=>r["chp_values"],
        "solver_objective_USD"=>r["solver_objective_USD"],
    )
    n=validate_r7_normal(nc, nr)
    out["normal_validation"]=n
    out["model_pass"]=all(x["pass"] for x in out["rows"])&&n["model_pass"]&&n["pipe_reference_pass"]
    out["cost_USD"]=n["cost_USD"]
    if haskey(r, "lower_bound_USD")
        isfinite(r["lower_bound_USD"]) || error("连续流量下界非有限")
        gap=(n["cost_USD"]-r["lower_bound_USD"])/max(1, abs(n["cost_USD"]))
        out["relative_gap"]=gap
        out["optimality_pass"]=out["model_pass"]&&-1e-6<=gap<=1e-4
    end
    out
end
