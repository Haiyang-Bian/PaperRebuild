using PaperRebuild, CSV, TOML, SHA
length(ARGS)>=1||error("参数：报告目录 [--seal] [--publish]")
dir=first(ARGS);
root=normpath(joinpath(@__DIR__, ".."))
meta=TOML.parsefile(joinpath(dir, "report.toml"));
config=joinpath(root, "configs", "r5", "dispatch", "study.toml")
rules=TOML.parsefile(config)
meta["schema"]=="r5-dispatch-report-v1"&&meta["origin"]=="synthetic"||error("报告身份错误")
bytes2hex(sha256(read(config)))==meta["config_sha256"]||error("规则改变")
bytes2hex(sha256(read(joinpath(@__DIR__, "report_r5_dispatch.jl"))))==meta["script_sha256"]||error(
    "报告生产脚本改变",
)
summary=collect(CSV.File(joinpath(dir, "comparison.csv")));
residuals=collect(CSV.File(joinpath(dir, "residuals.csv")))
expected=Set(x["id"] for x in rules["records"])
length(summary)==length(expected)==meta["records"]&&Set(x.record_id for x in summary)==expected||error(
    "正式清单不完整",
)
Set(keys(meta["raw_source_hashes"]))==expected||error("原值来源不完整")
count(x->x.model_pass, summary)==meta["model_pass"]&&count(x->x.cost_complete, summary)==meta["cost_complete"]||error(
    "汇总不一致",
)
for x in summary
    x.case_sha256==rules["input_sha256"][x.case]||error("输入不同")
    rr=filter(z->z.record_id==x.record_id, residuals)
    if x.candidate
        !isempty(rr)&&all(z.run_id==x.run_id for z in rr)||error("候选无残差或身份错")
        all(
            z.pass==(z.residual<=z.tolerance)&&isapprox(
                z.normalized,
                z.residual/z.tolerance;
                atol = 1e-12,
            ) for z in rr
        )||error("残差验收不同")
        model=all(z.pass for z in rr if z.group in ("electric", "heat", "comfort", "delivery"))
        model==x.model_pass||error("模型通过标志不同")
        isapprox(maximum(z.normalized for z in rr), x.maximum_normalized_residual; atol = 1e-12)||error(
            "残差最大值不同",
        )
        if x.cost_complete
            x.status=="solver_optimal"&&x.model_pass&&x.cost_pass&&x.auxiliary_exact_pass&&x.relative_gap<=1e-4||error(
                "费用认证不完整",
            )
        end
    else
        isempty(rr)&&!x.model_pass&&!x.cost_complete&&isnan(x.objective)||error("无解被伪装通过")
    end
end
for x in CSV.File(joinpath(dir, "solver-comparison.csv"))
    a, b=(only(filter(z->z.record_id==id, summary)) for id in (x.left, x.right))
    comparable=a.candidate&&b.candidate
    x.comparable==comparable||error("比较口径不同")
    if comparable
        gap=abs(a.objective-b.objective)/max(1, abs(a.objective), abs(b.objective))
        isapprox(gap, x.relative_objective_difference; atol = 1e-12)&&x.A2_pass==(
            a.cost_complete&&b.cost_complete&&gap<=1e-4
        )||error("A2不同")
    else
        !x.A2_pass&&isnan(x.relative_objective_difference)||error("失败比较变成功")
    end
end
fig=TOML.parsefile(joinpath(dir, "figure-config.toml"))
!fig["solver_reexecuted"]&&Set(fig["source_run_ids"])==Set(x.run_id for x in summary)||error(
    "图源身份不同",
)
bytes2hex(sha256(read(joinpath(@__DIR__, "plot_r5_dispatch.jl"))))==fig["script_sha256"]||error(
    "绘图入口变化",
)
for (file, hash) in fig["sources"]
    bytes2hex(sha256(read(joinpath(dir, file))))==hash||error("图源变化")
end
hashes=Dict{String,String}()
for file in readdir(dir)
    file=="artifact-hashes.toml"&&continue
    path=joinpath(dir, file)
    isfile(path)&&filesize(path)<=5*1024^2||error("报告文件超范围")
    if endswith(file, ".csv")||endswith(file, ".toml")
        occursin(r"(?i)[A-Z]:[\\/]|/Users/|/home/", read(path, String))&&error(
            "公开数据包含本机路径",
        )
    end
    hashes[file]=bytes2hex(sha256(read(path)))
end
seal=joinpath(dir, "artifact-hashes.toml")
if "--seal" in ARGS
    ispath(seal)&&error("不覆盖封存清单")
    write(seal, PaperRebuild.r5_market_text(Dict("sha256"=>hashes)))
else
    TOML.parsefile(seal)["sha256"]==hashes||error("封存改变")
end
if "--publish" in ARGS
    target=joinpath(root, "docs", "src", "assets", "r5-dispatch")
    for file in vcat(collect(keys(hashes)), ["artifact-hashes.toml"])
        src, dst=joinpath(dir, file), joinpath(target, file)
        if ispath(dst)
            read(src)==read(dst)||error("不覆盖文档旧证据")
        else
            mkpath(dirname(dst))
            cp(src, dst)
        end
    end
end
println(
    "IES evidence: complete frozen list, independent model/delivery/cost checks, figures and hashes verified.",
)
