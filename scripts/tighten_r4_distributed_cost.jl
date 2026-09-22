# 单独的保存值分析：只收紧成本上图变量，不改原运行、控制量、合同或求解状态。
using PaperRebuild, TOML, SHA, CSV
length(ARGS)==2 || error("参数：study.toml 报告目录")
study_path=abspath(ARGS[1]);
dir=dirname(study_path);
output=ARGS[2]
study=TOML.parsefile(study_path)
dest=joinpath(output, "cost-tightening.toml")
ispath(dest) && error("不覆盖已有上图审计")
records=Dict{String,Any}[];
summary=NamedTuple[]
for entry in study["records"]
    entry["purpose"]=="agnb" || continue
    loaded=read_r4_distributed_run(joinpath(dir, entry["id"]))
    c, r=loaded.case, loaded.result
    haskey(r, "candidate") || continue
    original=r["candidate"]
    corrected=deepcopy(original)
    s=corrected["values"]
    # 在当前采用模型中w只参与w>=a(pref-D)^2及正成本项，没有其他物理依赖。
    # qabs在合并候选中已经取abs(q)。局部fee副本不进入这个集中合同表示。
    for i in 1:3, carrier in ("P", "H"), t in 1:c.data["T"]
        params=c.data["actors"][i]
        scale=get(c.data, "preference_model", "")=="explicit_reference_v1" ?
              params["sat_"*carrier] : 1.0
        s["w_"*carrier][i][t]=params["sat_"*carrier]>0 ?
                              scale*(
            PaperRebuild.r4_preferred_demand(params, carrier, t)-s[carrier*"_D"][i][t]
        )^2 : 0.0
    end
    physical_keys=[k for k in keys(s) if !(k in ("w_P", "w_H"))]
    all(isequal(s[k], original["values"][k]) for k in physical_keys) ||
        error("重构改变了物理或合同变量")
    cost=PaperRebuild.r4_trading_ledger(c, s)["aggregator_cost"]
    cost<=original["solver_objective"]+1e-8 || error("收紧后成本反而增加")
    # 这里是重构后的数学目标，不是求解器新返回的目标；原值及状态单独保留。
    corrected["solver_objective"]=cost
    corrected["objective_origin"]="analytical_cost_epigraph_tightening_not_solver_output"
    corrected["raw_solver_objective"]=original["solver_objective"]
    corrected["cost_optimization_complete"]=false
    corrected["status"]="postprocessed_candidate_not_new_solver_run"
    val=validate_r4_trading(c, corrected)
    original_cost=PaperRebuild.r4_trading_ledger(c, original["values"])["aggregator_cost"]
    cost==original_cost || error("重构改变实际资源和交易费用")
    hashdict=Dict(k=>s[k] for k in physical_keys)
    physical_hash=bytes2hex(sha256(PaperRebuild.r4_text(hashdict)))
    push!(
        records,
        Dict(
            "run_id"=>entry["id"],
            "input_sha256"=>c.sha256,
            "source_result_sha256"=>bytes2hex(
                sha256(read(joinpath(dir, entry["id"], "result.toml"))),
            ),
            "raw_status"=>r["status"],
            "raw_model_pass"=>original["validation"]["model_pass"],
            "raw_solver_objective"=>original["solver_objective"],
            "reconstructed_objective"=>cost,
            "unchanged_physical_and_contract_sha256"=>physical_hash,
            "changes_only_w_P_w_H"=>true,
            "reconstructed_values"=>s,
            "reconstructed_validation"=>val,
            "not_a_new_solver_certificate"=>true,
        ),
    )
    push!(
        summary,
        (
            run_id = entry["id"],
            raw_status = r["status"],
            raw_A1 = original["validation"]["model_pass"],
            reconstructed_A1 = val["model_pass"],
            raw_solver_objective = original["solver_objective"],
            recomputed_cost = cost,
            controls_unchanged = true,
            cost_unchanged = true,
            network_checked = false,
        ),
    )
end
write(
    dest,
    PaperRebuild.r4_text(
        Dict(
            "records"=>records,
            "script_sha256"=>bytes2hex(sha256(read(@__FILE__))),
            "source_study_sha256"=>bytes2hex(sha256(read(study_path))),
            "proof"=>"w only appears as a lower cost epigraph and with positive cost coefficient; controls and all contracts identical",
        ),
    ),
)
CSV.write(joinpath(output, "cost-tightening.csv"), summary)
println(
    "Independent cost-epigraph tightening: ",
    count(x->x.reconstructed_A1, summary),
    "/",
    length(summary),
    "; raw verdicts unchanged.",
)
