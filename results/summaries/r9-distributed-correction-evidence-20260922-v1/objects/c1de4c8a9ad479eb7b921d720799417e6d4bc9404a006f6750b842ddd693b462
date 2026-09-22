"""
    r3_stopping_evidence(case, result)

只读重建各轮停止条件。费用用案例货币单位；原文未确认数值ε时仅并列1e-6/1e-4/1e-2
绝对阈值。项目仍需连续三次接受的小变化、可信方向和非活跃信赖域；不修改历史判定。
局部KKT从该次局部问题读取，不借用固定流量子问题的乘子。
"""
function r3_stopping_evidence(c::R2Case, result)
    get(result, "algorithm", "")=="r3_paper_structure_v1" && return r3_baseline_evidence(c, result)
    rows=Dict{String,Any}[]
    small=0
    previous=nothing
    for it in get(result, "iterations", Any[])
        stage=result["stages"][it["stage"]]
        dispatch=it["mode"]=="dispatch"
        row=Dict{String,Any}(
            "iteration"=>it["iteration"],
            "mode"=>it["mode"],
            "small_accepted_before"=>small,
            "original_outer_status"=>result["outer_status"],
            "trusted_sensitivity"=>get(it, "trusted_sensitivity", false),
            "smooth"=>get(it, "smooth", false),
            "stage"=>it["stage"],
            "model_pass"=>get(stage, "model_pass", false),
            "physical_pass"=>get(stage, "physics_pass", false),
            "objective_kind"=>get(stage, "objective_kind", "unknown"),
        )
        if dispatch
            cost=stage["operating_cost"]
            row["cost"]=cost
            if !isnothing(previous)
                delta=abs(cost-previous)
                row["absolute_change"]=delta
                row["relative_change"]=delta/max(1, abs(previous))
                for e in (1e-6, 1e-4, 1e-2)
                    row["paper_form_epsilon_"*string(e)]=delta<=e
                end
            end
            previous=cost
        else
            previous=nothing
        end
        for key in ("projected_gradient_norm", "local_direction_norm", "local_trust_binding")
            haskey(it, key) && (row[key]=it[key])
        end
        locals=[t["local"] for t in it["trials"] if haskey(t, "local")]
        if !isempty(locals)
            local_result=last(locals)
            row["local_status"]=local_result["status"]
            row["local_kkt_trusted"]=get(get(local_result, "kkt", Dict()), "trusted", false)
            row["local_kkt_reason"]=get(get(local_result, "kkt", Dict()), "reason", "not_recorded")
            haskey(local_result, "predicted_merit") &&
                (row["predicted_improvement"]=it["merit"]-local_result["predicted_merit"])
        end
        row["old_pg_stop"]=dispatch &&
                           small>=3 &&
                           get(row, "smooth", false) &&
                           get(row, "trusted_sensitivity", false) &&
                           get(row, "projected_gradient_norm", Inf)<=1e-4
        row["old_local_stop"]=dispatch &&
                              small>=3 &&
                              get(row, "local_kkt_trusted", false) &&
                              !get(row, "local_trust_binding", true) &&
                              get(row, "local_direction_norm", Inf)<=1e-4 &&
                              isempty(get(it, "switches", String[]))
        accepted=findfirst(t->get(t, "accepted", false), it["trials"])
        if !isnothing(accepted)
            trial=it["trials"][accepted]
            if dispatch && get(trial, "mode", "")=="dispatch"
                after=result["stages"][trial["stage"]]["operating_cost"]
                delta=abs(after-stage["operating_cost"])/max(1, abs(stage["operating_cost"]))
                small=delta<=1e-6 ? small+1 : 0
                row["accepted_relative_change"]=delta
            else
                small=0
            end
        end
        row["small_accepted_after"]=small
        push!(rows, row)
    end
    return rows
end

# 用原A1逐项归一化；最大值用于候选排序，不作为新的验收容差。
function r3_physical_score(c, r)
    haskey(r, "values") || return Inf
    report=validate_r3_solution(c, r)
    return maximum((x.residual/x.tolerance for x in report.rows); init = 0.0)
end

"""
    audit_r3_failure(loaded; reference=nothing)

对read_r3_run已核验的运行只读提取初始化、首个/最低费/最小残差/最近可行阶段及末次失败。
返回支路原等式、损耗、电压和购电状态及停止证据。参考独立保存，绝不注入PG。
“最小残差”是原A1归一化后的排序值，不是修改过的成功判据。
"""
function audit_r3_failure(loaded; reference = nothing)
    c, r=loaded.case, loaded.result
    stages=r["stages"]
    eligible=findall(
        s->get(s, "model_pass", false) &&
           get(s, "objective_kind", "")=="operating_cost" &&
           get(s, "stage", "")!="pressure_reconstruction" &&
           haskey(s, "values") &&
           r2_spec_from_dict(s["spec"])==R2Spec(),
        stages,
    )
    chosen=Dict{String,Int}()
    if !isempty(eligible)
        chosen["first_feasible"]=first(eligible)
        chosen["last_feasible"]=last(eligible)
        chosen["minimum_cost"]=eligible[argmin(stages[i]["operating_cost"] for i in eligible)]
        scores=[r3_physical_score(c, reconstruct_r3_pressure(c, stages[i])) for i in eligible]
        chosen["minimum_violation"]=eligible[argmin(scores)]
    end
    init=findfirst(s->haskey(s, "values"), stages)
    isnothing(init) || (chosen["initialization"]=init)
    chosen["last_stage"]=length(stages)
    selected=Dict{String,Any}[]
    electrical=Dict{String,Any}[]
    for (name, i) in sort!(collect(chosen); by = first)
        s=stages[i]
        push!(selected, Dict("role"=>name, "stage_index"=>i, "record"=>deepcopy(s)))
        haskey(s, "values") || continue
        v=s["values"]
        d=c.data
        for (b, e) in enumerate(d["electric"]["edges"]), t in 1:d["T"]
            vi=v["v"][e["from"]][t]
            ell=v["ell"][b][t]
            P, Q=v["P_branch"][b][t], v["Q_branch"][b][t]
            push!(
                electrical,
                Dict(
                    "role"=>name,
                    "stage"=>i,
                    "branch"=>b,
                    "t"=>t,
                    "v_from_pu2"=>vi,
                    "v_to_pu2"=>v["v"][e["to"]][t],
                    "ell_pu2"=>ell,
                    "P_pu"=>P,
                    "Q_pu"=>Q,
                    "SOC_slack"=>vi*ell-P^2-Q^2,
                    "loss_MW"=>d["electric"]["base_MVA"]*e["r_pu"]*ell,
                    "grid_MW"=>v["P_grid"][t],
                ),
            )
        end
    end
    out=Dict{String,Any}(
        "schema"=>"r3-failure-audit-v1",
        "input_sha256"=>c.sha256,
        "source_metadata"=>loaded.metadata,
        "source_run_id"=>loaded.metadata["run_id"],
        "selected"=>selected,
        "electrical"=>electrical,
        "stopping"=>r3_stopping_evidence(c, r),
        "historical_status"=>r["outer_status"],
    )
    if !isnothing(reference)
        reference.case.sha256==c.sha256 || throw(ArgumentError("参考输入不同"))
        out["reference_final"]=reference.result["stages"][reference.result["final_stage"]]
        out["reference_run_id"]=reference.metadata["run_id"]
    end
    return out
end
