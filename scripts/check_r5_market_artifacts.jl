using PaperRebuild, TOML, CSV, SHA
args=filter(x->!startswith(x, "--"), ARGS)
length(args)==1 || error("参数：报告目录 [--seal] [--publish]")
dir=only(args)
root=normpath(joinpath(@__DIR__, ".."))
rules=TOML.parsefile(joinpath(root, "configs", "r5", "market", "study.toml"))
meta=TOML.parsefile(joinpath(dir, "report.toml"))
meta["schema"]=="r5-market-report-v1" && meta["origin"]=="synthetic" || error("报告身份错误")
meta["config_sha256"]==bytes2hex(
    sha256(read(joinpath(root, "configs", "r5", "market", "study.toml"))),
) || error("冻结规则变化")
meta["script_sha256"]==bytes2hex(sha256(read(joinpath(@__DIR__, "report_r5_market.jl")))) ||
    error("报告脚本变化")
summary=collect(CSV.File(joinpath(dir, "comparison.csv")))
residuals=collect(CSV.File(joinpath(dir, "residuals.csv")))
expected=Set(x["id"] for x in rules["records"])
length(summary)==length(expected) && Set(x.record_id for x in summary)==expected ||
    error("报告缺少正式记录")
length(unique(x.run_id for x in summary))==length(summary) || error("运行ID重复")
for r in summary
    r.case_sha256==rules["input_sha256"][r.case] || error("输入哈希不符")
    rows=filter(x->x.record_id==r.record_id, residuals)
    r.candidate==!isempty(rows) || error("候选与残差矛盾")
    for x in rows
        x.pass==(isfinite(x.residual)&&x.residual<=x.tolerance) || error("残差门槛被改变")
        isapprox(x.normalized, x.residual/x.tolerance; atol = 0, rtol = 1e-12) ||
            error("残差归一化错误")
    end
    r.model_pass==(r.candidate&&all(x.pass for x in rows if x.scope!="dual")) ||
        error("模型验收错误")
    r.kkt_pass &&
        !(
            r.model_pass&&all(x.pass for x in rows if x.scope=="dual")&&any(
                x.id=="R5-MK_MOI_conversion" for x in rows
            )
        ) &&
        error("KKT证据缺失")
    r.optimality_pass==(r.model_pass&&r.kkt_pass&&r.relative_gap<=1e-4) || error("最优性状态错误")
    r.cost_optimization_complete==(r.status=="solver_optimal"&&r.optimality_pass) ||
        error("求解完成状态错误")
    if r.candidate
        isapprox(
            r.relative_gap,
            abs(r.objective-r.dual_value)/max(1.0, abs(r.objective));
            atol = 1e-12,
        ) || error("原对偶差错误")
    else
        all(isnan, (r.objective, r.dual_value, r.relative_gap)) || error("失败被填入虚假费用")
    end
end
for (key, field) in (
    ("model_pass", :model_pass),
    ("kkt_pass", :kkt_pass),
    ("cost_complete", :cost_optimization_complete),
    ("independent_dual_pass", :independent_dual_pass),
)
    meta[key]==count(x->getproperty(x, field), summary) || error("状态计数错误")
end
components=collect(CSV.File(joinpath(dir, "objective-components.csv")))
for r in summary
    r.candidate || continue
    rows=filter(x->x.record_id==r.record_id, components)
    length(rows)==6 &&
    abs(sum(x.amount_USD for x in rows)-r.objective)<=1e-6*max(1.0, abs(r.objective)) ||
        error("报价目标分项不守恒")
end
for x in CSV.File(joinpath(dir, "solver-comparison.csv"))
    a, b=(only(filter(r->r.record_id==id, summary)) for id in (x.left_record, x.right_record))
    a.case_sha256==b.case_sha256 || error("不同输入混成同模型对照")
    x.comparable==(a.candidate&&b.candidate) || error("比较状态错误")
    if x.comparable
        gap=abs(a.objective-b.objective)/max(1.0, abs(a.objective), abs(b.objective))
        isapprox(x.relative_objective_difference, gap; atol = 1e-12) &&
        x.A2_pass==(gap<=1e-4&&a.optimality_pass&&b.optimality_pass) || error("A2比较错误")
    else
        !x.A2_pass && isnan(x.relative_objective_difference) || error("失败被报告为通过")
    end
end
fig=TOML.parsefile(joinpath(dir, "figure-config.toml"))
replay_path=joinpath(dir, "environment-replay.toml")
if isfile(replay_path)
    replay=TOML.parsefile(replay_path)
    replay["schema"]=="r5-market-environment-replay-v1" &&
    replay["rules_unchanged"] &&
    replay["model_and_validator_unchanged"] || error("环境复核口径变化")
    replay["config_sha256"]==meta["config_sha256"] &&
    replay["new_study_sha256"]==meta["study_sha256"] || error("复核批次身份变化")
    replay["script_sha256"]==bytes2hex(
        sha256(read(joinpath(@__DIR__, "audit_r5_market_replay.jl"))),
    ) || error("复核生产脚本变化")
    length(replay["records"])==length(expected) &&
    Set(x["record_id"] for x in replay["records"])==expected || error("复核配对缺失")
    for x in replay["records"]
        r=only(filter(z->z.record_id==x["record_id"], summary))
        r.run_id==x["new_run_id"] &&
        r.case_sha256==x["case_sha256"] &&
        r.status==x["new_status"] &&
        r.optimality_pass==x["new_optimality_pass"] || error("复核记录与摘要不一致")
        x["new_result_sha256"]==meta["raw_source_hashes"][x["record_id"]] ||
            error("复核原值来源变化")
        x["old_optimality_pass"] &&
            !x["same_model_comparison"]["A2_pass"] &&
            error("旧合格目标未通过同模型复核")
    end
end
!fig["solver_reexecuted"] && Set(fig["source_run_ids"])==Set(x.run_id for x in summary) ||
    error("图源身份不一致")
fig["script_sha256"]==bytes2hex(sha256(read(joinpath(@__DIR__, "plot_r5_market.jl")))) ||
    error("绘图脚本改变")
for (file, hash) in fig["sources"]
    bytes2hex(sha256(read(joinpath(dir, file))))==hash || error("图源改变")
end
hashes=Dict{String,String}()
for file in readdir(dir)
    file=="artifact-hashes.toml" && continue
    path=joinpath(dir, file)
    isfile(path) && filesize(path)<=5*1024^2 || error("报告文件超出发布范围")
    if endswith(file, ".csv")||endswith(file, ".toml")
        occursin(r"(?i)[A-Z]:[\\/]|/Users/|/home/", read(path, String)) &&
            error("公开结果包含本机绝对路径")
    end
    hashes[file]=bytes2hex(sha256(read(path)))
end
seal=joinpath(dir, "artifact-hashes.toml")
if "--seal" in ARGS
    ispath(seal) && error("拒绝覆盖封存清单")
    write(seal, PaperRebuild.r5_market_text(Dict("sha256"=>hashes)))
else
    TOML.parsefile(seal)["sha256"]==hashes || error("封存证据改变")
end
if "--publish" in ARGS
    target=joinpath(root, "docs", "src", "assets", "r5-market")
    for file in vcat(collect(keys(hashes)), ["artifact-hashes.toml"])
        src, dst=joinpath(dir, file), joinpath(target, file)
        if ispath(dst)
            read(src)==read(dst) || error("不覆盖已有文档证据")
        else
            mkpath(dirname(dst))
            cp(src, dst)
        end
    end
end
println(
    "Market evidence: complete frozen list, primal/KKT/objective comparisons, figures and hashes checked.",
)
