using PaperRebuild, TOML, SHA, CSV
args=filter(x->!startswith(x, "--"), ARGS)
length(args)==1 || error("参数：报告目录 [--seal] [--publish]")
dir=only(args)
root=normpath(joinpath(@__DIR__, ".."))
d=TOML.parsefile(joinpath(root, "configs", "r4", "distributed-study.toml"))
rows=collect(CSV.File(joinpath(dir, "comparison.csv")))
length(rows)==d["expected_distributed_runs"] &&
length(unique(x.run_id for x in rows))==length(rows) || error("运行缺失/重复")
for x in rows
    expected=x.reference_A2&&x.model_A1&&isfinite(x.relative_cost_difference)&&x.relative_cost_difference<=d["cost_relative_tolerance"]
    expected==x.cost_A4 || error("费用判定不一致")
    x.status=="consensus_converged" && !(x.consensus_A4&&x.model_A1) && error("停止证据不足")
    x.purpose=="agnb" && x.electric_original_A1 && error("AGNB不能声明网络通过")
    x.input_sha256==d["input_sha256"][x.case] || error("冻结输入改变")
end
meta=TOML.parsefile(joinpath(dir, "report.toml"))
meta["script_sha256"]==bytes2hex(sha256(read(joinpath(@__DIR__, "report_r4_distributed.jl")))) ||
    error("报告脚本变化")
meta["config_sha256"]==bytes2hex(
    sha256(read(joinpath(root, "configs", "r4", "distributed-study.toml"))),
) || error("冻结清单变化")
fig=TOML.parsefile(joinpath(dir, "figure-config.toml"))
for (file, script) in (
    ("audit.toml", "audit_r4_distributed.jl"),
    ("cost-tightening.toml", "tighten_r4_distributed_cost.jl"),
)
    TOML.parsefile(joinpath(dir, file))["script_sha256"]==bytes2hex(
        sha256(read(joinpath(@__DIR__, script))),
    ) || error("审计脚本改变")
end
tight=TOML.parsefile(joinpath(dir, "cost-tightening.toml"))
length(tight["records"])==8 || error("AGNB上图审计缺失")
for entry in tight["records"]
    name=first(split(entry["run_id"], "--"))
    c=load_r4_case(joinpath(root, "configs", "r4", "baseline", name*".toml"))
    c.sha256==entry["input_sha256"] || error("上图审计输入不同")
    candidate=Dict(
        "input_sha256"=>c.sha256,
        "spec"=>PaperRebuild.r4_spec(R4Spec(), c),
        "values"=>entry["reconstructed_values"],
        "solver_objective"=>entry["reconstructed_objective"],
    )
    validate_r4_trading(c, candidate)==entry["reconstructed_validation"] ||
        error("重构候选验收改变")
    control=Dict(k=>v for (k, v) in candidate["values"] if !(k in ("w_P", "w_H")))
    bytes2hex(sha256(PaperRebuild.r4_text(control)))==entry["unchanged_physical_and_contract_sha256"] ||
        error("重构控制哈希改变")
end
fig["script_sha256"]==bytes2hex(sha256(read(joinpath(@__DIR__, "plot_r4_distributed.jl")))) ||
    error("图脚本变化")
for (file, h) in fig["source_sha256"]
    bytes2hex(sha256(read(joinpath(dir, file))))==h || error("图源变化")
end
hs=Dict{String,String}()
for (folder, _, files) in walkdir(dir), file in files
    file=="artifact-hashes.toml" && continue
    path=joinpath(folder, file)
    stat(path).size<=5*1024^2 || error("摘要文件过大")
    if endswith(file, ".toml")||endswith(file, ".csv")
        occursin(r"(?i)[A-Z]:[\\/]|/Users/|/home/", read(path, String)) && error("本机路径泄漏")
    end
    hs[replace(relpath(path, dir), '\\'=>'/')]=bytes2hex(sha256(read(path)))
end
manifest=joinpath(dir, "artifact-hashes.toml")
if "--seal" in ARGS
    ispath(manifest) && error("不重封旧报告")
    write(manifest, PaperRebuild.r4_text(Dict("sha256"=>hs)))
else
    TOML.parsefile(manifest)["sha256"]==hs || error("摘要变化")
end
if "--publish" in ARGS
    target=joinpath(root, "docs", "src", "assets", "r4-distributed")
    for rel in vcat(collect(keys(hs)), ["artifact-hashes.toml"])
        src=joinpath(dir, rel)
        dst=joinpath(target, rel)
        if isfile(dst)
            read(src)==read(dst) || error("不覆盖不同摘要")
        else
            mkpath(dirname(dst))
            cp(src, dst)
        end
    end
end
println("R4 distributed: frozen scope, verdicts, figures and portable artifacts checked.")
