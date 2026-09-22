using PaperRebuild, TOML, CSV, SHA
args=filter(x->!startswith(x, "--"), ARGS)
length(args)==1 || error("参数：报告目录 [--seal] [--publish]")
dir=only(args)
root=normpath(joinpath(@__DIR__, ".."))
meta=TOML.parsefile(joinpath(dir, "report.toml"))
config=joinpath(root, "configs", "r4", "thermal-study.toml")
rules=TOML.parsefile(config)
meta["origin"]=="synthetic" || error("来源标记错误")
meta["config_sha256"]==bytes2hex(sha256(read(config))) || error("规则变化")
meta["script_sha256"]==bytes2hex(sha256(read(joinpath(@__DIR__, "report_r4_thermal.jl")))) ||
    error("报告脚本变化")
rows=collect(CSV.File(joinpath(dir, "comparison.csv")))
residuals=collect(CSV.File(joinpath(dir, "residuals.csv")))
expected=Set(x["id"] for x in rules["records"])
length(rows)==length(expected) && Set(x.run_id for x in rows)==expected || error("清单不完整")
for x in rows
    rr=filter(z->z.run_id==x.run_id, residuals)
    x.candidate==!isempty(rr) || error("缺解/残差状态冲突")
    if x.candidate
        x.max_normalized_residual==maximum(z.normalized for z in rr) || error("残差摘要不符")
        all(z.pass==(isfinite(z.residual)&&z.residual<=z.tolerance) for z in rr) ||
            error("残差门槛错误")
        all(isapprox(z.normalized, z.residual/z.tolerance; atol = 0, rtol = 1e-12) for z in rr) ||
            error("残差单位错误")
        x.model_pass==all(z.pass for z in rr if z.scope!="electric_original") ||
            error("模型判定不符")
        x.electric_original_pass==all(z.pass for z in rr if z.scope=="electric_original") ||
            error("原电网判定不符")
    end
    x.adopted_physical_pass==(x.model_pass&&x.electric_original_pass) || error("物理状态混用")
    x.cost_optimization_complete &&
        !(x.model_pass&&isfinite(x.relative_gap)&&x.relative_gap<=1e-4) &&
        error("费用认证错误")
end
meta["saved"]==length(rows) &&
meta["model_pass"]==count(x->x.model_pass, rows) &&
meta["adopted_physical_pass"]==count(x->x.adopted_physical_pass, rows) &&
meta["cost_complete"]==count(x->x.cost_optimization_complete, rows) || error("计数错误")
states=collect(CSV.File(joinpath(dir, "states.csv")))
for x in rows
    x.candidate || continue
    ss=filter(z->z.run_id==x.run_id, states)
    length(ss)==24 || error("状态轨迹缺失")
    abs(sum(z.loss_MW for z in ss)-x.heat_loss_MWh)<=1e-10 || error("热损耗积分不符")
end
policies=collect(CSV.File(joinpath(dir, "policy-comparison.csv")))
length(policies)==8 || error("策略配对缺失")
for x in policies
    a=only(filter(r->r.run_id==x.fixed_run, rows))
    b=only(filter(r->r.run_id==x.joint_run, rows))
    a.case==b.case==x.case && a.loss==b.loss==x.loss && a.policy=="fixed" && b.policy=="joint" ||
        error("策略配对改变了其他因素")
    valid=a.adopted_physical_pass&&b.adopted_physical_pass
    valid==x.eligible || error("未验算候选进入费用比较")
    if valid
        isapprox(x.candidate_saving, a.operating_cost-b.operating_cost; atol = 1e-10) &&
        isapprox(
            x.candidate_saving_percent,
            100x.candidate_saving/abs(a.operating_cost);
            atol = 1e-10,
        ) || error("候选费用差计算不一致")
        isfinite(a.objective_bound) &&
            !isapprox(x.saving_bound_lower, a.objective_bound-b.operating_cost; atol = 1e-10) &&
            error("收益下界计算错误")
        isfinite(b.objective_bound) &&
            !isapprox(x.saving_bound_upper, a.operating_cost-b.objective_bound; atol = 1e-10) &&
            error("收益上界计算错误")
    else
        all(
            isnan,
            (
                x.candidate_saving,
                x.candidate_saving_percent,
                x.saving_bound_lower,
                x.saving_bound_upper,
            ),
        ) || error("失败配对出现虚假费用收益")
    end
end
legacy=collect(CSV.File(joinpath(dir, "legacy-comparison.csv")))
length(legacy)==16 && Set(x.run_id for x in legacy)==expected || error("父模型比较缺失")
for x in legacy
    r=only(filter(y->y.run_id==x.run_id, rows))
    r.adopted_physical_pass==x.new_steady_pass || error("父模型比较判定不一致")
    r.candidate &&
        !isapprox(x.new_minus_legacy, r.operating_cost-x.legacy_cost; atol = 1e-10) &&
        error("父模型费用差计算错误")
    startswith(x.interpretation, "Combined idle-temperature-mixing") ||
        error("不同模型费用被当成同模型最优间隙")
end
fig=TOML.parsefile(joinpath(dir, "figure-config.toml"))
!fig["solver_reexecuted"] && Set(fig["source_run_ids"])==expected || error("图源身份冲突")
fig["script_sha256"]==bytes2hex(sha256(read(joinpath(@__DIR__, "plot_r4_thermal.jl")))) ||
    error("绘图脚本变化")
for (f, hash) in fig["sources"]
    bytes2hex(sha256(read(joinpath(dir, f))))==hash || error("图源哈希变化")
end
hashes=Dict{String,String}()
for file in readdir(dir)
    file=="artifact-hashes.toml" && continue
    path=joinpath(dir, file)
    filesize(path)<=5*1024^2 || error("单文件超过公开体积限制")
    if endswith(file, ".csv")||endswith(file, ".toml")
        occursin(r"(?i)[A-Z]:[\\/]|/Users/|/home/", read(path, String)) && error("本机绝对路径")
    end
    hashes[file]=bytes2hex(sha256(read(path)))
end
seal=joinpath(dir, "artifact-hashes.toml")
if "--seal" in ARGS
    ispath(seal) && error("拒绝重复封存")
    write(seal, PaperRebuild.r4_text(Dict("sha256"=>hashes)))
else
    TOML.parsefile(seal)["sha256"]==hashes || error("封存文件变化")
end
if "--publish" in ARGS
    target=joinpath(root, "docs", "src", "assets", "r4-thermal")
    for file in vcat(collect(keys(hashes)), ["artifact-hashes.toml"])
        src, dst=joinpath(dir, file), joinpath(target, file)
        if ispath(dst)
            read(src)==read(dst) || error("不覆盖已有证据")
        else
            mkpath(dirname(dst))
            cp(src, dst)
        end
    end
end
println(
    "Thermal evidence checked: 16 runs, independent residuals, figure data and portable hashes.",
)
