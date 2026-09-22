using PaperRebuild, CSV, TOML, SHA
function audit_r5_dispatch(study_path, dir)
    study=TOML.parsefile(study_path)
    study["complete"]||error("批次未完成")
    dest=joinpath(dir, "mechanism-audit.toml")
    ispath(dest)&&error("不覆盖已存在机制证据")
    summary=collect(CSV.File(joinpath(dir, "comparison.csv")))
    residuals=collect(CSV.File(joinpath(dir, "residuals.csv")))
    comparisons=collect(CSV.File(joinpath(dir, "solver-comparison.csv")))
    loadrun(name) = read_r5_dispatch_run(joinpath(dirname(study_path), name*"--highs"))
    proofs=Dict{String,Any}[]
    for name in ("unavailable", "market_up_full")
        x=loadrun(name)
        d=x.case.data
        h=d["heat"]
        s=only(h["sources"])
        p=only(h["pipes"])
        b=only(d["buildings"])
        s["T_min_K"]==s["T_max_K"]&&b["R_min_K"]==b["R_max_K"]&&p["loss_W_mK"]==0 ||
            error("解析反例温度/损耗假设不成立")
        all(t==b["R_min_K"] for t in p["history_R_K"])&&b["P_DH_max_MW"]==0 ||
            error("解析反例历史/本地热假设不成立")
        devices=d["devices"]
        Set(z["kind"] for z in devices)==Set(["EB", "GT"])||error("解析反例设备不同")
        eb=only(filter(z->z["kind"]=="EB", devices))
        gt=only(filter(z->z["kind"]=="GT", devices))
        heat=h["c_J_kgK"]*s["m_kg_s"]*(s["T_min_K"]-b["R_min_K"])/1e6
        floor=[
            sum(v[t] for v in d["electric"]["P_load_MW"])+heat/eb["heat_ratio"]-gt["p_max_MW"] for
            t in 1:d["T"]
        ]
        request=d["realtime"]["alpha_up"] .* d["award"]["R_up_MW"]-d["realtime"]["alpha_down"] .*
                                                                   d["award"]["R_down_MW"]
        target=d["award"]["P_DA_MW"]-request
        d["realtime"]["delta"]==0 && all(floor .> target .+ 1e-6) ||
            error("未形成要求的硬交付容量矛盾")
        push!(
            proofs,
            Dict(
                "case"=>name,
                "case_sha256"=>x.case.sha256,
                "run_id"=>x.result["run_id"],
                "source_status"=>x.result["status"],
                "minimum_import_MW"=>floor,
                "requested_import_MW"=>target,
                "capacity_conflict"=>true,
                "proof"=>"Constant source and return temperatures, no loss, only EB/GT and no local heater: required EB electricity plus base load minus maximum GT output bounds PCC import.",
            ),
        )
    end
    cap=loadrun("capacity_denominator")
    v=cap.validation
    unmet=sum(v["mismatch_MW"])/sum(abs.(v["request_MW"]))
    hand, local_run, quarter=(loadrun(n) for n in ("hand", "local_heat", "quarter"))
    v["model_pass"]&&isapprox(unmet, 1.0; atol = 1e-8)||error("容量分母见证不成立")
    isapprox(
        hand.validation["operating_net_cost"],
        local_run.validation["operating_net_cost"];
        atol = 1e-8,
    )||error("供热互换手算不一致")
    isapprox(
        quarter.validation["operating_net_cost"],
        hand.validation["operating_net_cost"]/4;
        atol = 1e-8,
    )||error("时间步费用换算不一致")
    audit=Dict(
        "schema"=>"r5-dispatch-mechanism-audit-v1",
        "origin"=>"synthetic",
        "study_sha256"=>bytes2hex(sha256(read(study_path))),
        "config_sha256"=>study["config_sha256"],
        "script_sha256"=>bytes2hex(sha256(read(@__FILE__))),
        "proofs"=>proofs,
        "records"=>length(summary),
        "model_pass"=>count(x->x.model_pass, summary),
        "cost_complete"=>count(x->x.cost_complete, summary),
        "residual_count"=>length(residuals),
        "max_normalized_residual"=>maximum(x.normalized for x in residuals),
        "max_relative_gap"=>maximum(x.relative_gap for x in summary if x.cost_complete),
        "max_elapsed_sec"=>maximum(x.elapsed_sec for x in summary),
        "comparable_pairs"=>count(x->x.comparable, comparisons),
        "A2_pass_pairs"=>count(x->x.A2_pass, comparisons),
        "max_solver_objective_difference"=>maximum(
            x.relative_objective_difference for x in comparisons if x.comparable
        ),
        "capacity_denominator"=>Dict(
            "run_id"=>cap.result["run_id"],
            "model_pass"=>v["model_pass"],
            "request_MWh"=>cap.case.data["dt_h"]*sum(abs.(v["request_MW"])),
            "unmet_fraction_of_request"=>unmet,
            "mismatch_MWh"=>v["mismatch_MWh"],
            "allowed_MWh"=>v["mismatch_limit_MWh"],
        ),
        "hand_checks"=>Dict(
            "district_cost"=>hand.validation["operating_net_cost"],
            "local_cost"=>local_run.validation["operating_net_cost"],
            "quarter_cost"=>quarter.validation["operating_net_cost"],
            "max_temperature_difference_K"=>maximum(
                abs.(hand.result["values"]["τ_IN"][1]-local_run.result["values"]["τ_IN"][1]),
            ),
        ),
    )
    write(dest, PaperRebuild.r5_market_text(audit))
    println(
        "IES mechanisms: ",
        audit["model_pass"],
        "/",
        audit["records"],
        " model; max residual/tol=",
        audit["max_normalized_residual"],
        "; solver pairs=",
        audit["A2_pass_pairs"],
        "/",
        audit["comparable_pairs"],
        "; permitted unmet fraction=",
        unmet,
    )
    for x in summary
        println(x.record_id, " | ", x.status, " | cost=", x.objective, " | gap=", x.relative_gap)
    end
end
length(ARGS)==2||error("参数：已完成study.toml 已有报告目录")
audit_r5_dispatch(ARGS...)
