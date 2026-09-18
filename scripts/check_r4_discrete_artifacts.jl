using PaperRebuild, TOML, CSV, SHA
args=filter(x->!startswith(x, "--"), ARGS)
length(args)==1 || error("参数：报告目录 [--seal] [--publish]")
dir=only(args)
root=normpath(joinpath(@__DIR__, ".."))
meta=TOML.parsefile(joinpath(dir, "report.toml"))
d=TOML.parsefile(joinpath(root, "configs", "r4", "discrete-study.toml"))
meta["config_sha256"]==bytes2hex(
    sha256(read(joinpath(root, "configs", "r4", "discrete-study.toml"))),
) || error("规则改变")
meta["script_sha256"]==bytes2hex(sha256(read(joinpath(@__DIR__, "report_r4_discrete.jl")))) ||
    error("报告脚本改变")
rows=collect(CSV.File(joinpath(dir, "comparison.csv")))
modes=collect(CSV.File(joinpath(dir, "modes.csv")))
length(rows)==20&&length(unique(x.run_id for x in rows))==20 || error("运行不完整")
length(modes)==128 || error("模式结果不完整")
for name in d["cases"]
    for method in ("distributed", "central_enumeration")
        rr=filter(x->x.case==name&&x.method==method, modes)
        sort([x.pattern for x in rr])==collect(1:16) || error("模式覆盖不完整")
    end
end
for x in rows
    x.input_sha256==d["input_sha256"][x.case] || error("输入不同")
    x.method=="distributed"&&x.certificate_A2&&error("分布法不能伪造全局界")
    x.cost_A4&&!(
        x.model_A1&&x.same_model_comparison&&x.relative_cost_difference<=d["relative_cost_A4"]
    )&&error("费用比较错误")
    x.certificate_A2&&!(x.model_A1&&isfinite(x.relative_gap)&&x.relative_gap<=d["gap_A2"])&&error(
        "认证证据错误",
    )
end
fig=TOML.parsefile(joinpath(dir, "figure-config.toml"))
fig["script_sha256"]==bytes2hex(sha256(read(joinpath(@__DIR__, "plot_r4_discrete.jl")))) ||
    error("绘图脚本改变")
for (f, h) in fig["sources"]
    bytes2hex(sha256(read(joinpath(dir, f))))==h || error("图源改变")
end
hs=Dict{String,String}()
for (folder, _, files) in walkdir(dir), file in files
    file=="artifact-hashes.toml"&&continue
    path=joinpath(folder, file)
    stat(path).size<=5*1024^2 || error("摘要单文件过大")
    if endswith(file, ".toml")||endswith(file, ".csv")
        occursin(r"(?i)[A-Z]:[\\/]|/Users/|/home/", read(path, String))&&error("本机路径")
    end
    hs[replace(relpath(path, dir), '\\'=>'/')]=bytes2hex(sha256(read(path)))
end
manifest=joinpath(dir, "artifact-hashes.toml")
if "--seal" in ARGS
    ispath(manifest)&&error("不重新封存")
    write(manifest, PaperRebuild.r4_text(Dict("sha256"=>hs)))
else
    TOML.parsefile(manifest)["sha256"]==hs || error("摘要哈希改变")
end
if "--publish" in ARGS
    target=joinpath(root, "docs", "src", "assets", "r4-discrete")
    for rel in vcat(collect(keys(hs)), ["artifact-hashes.toml"])
        src=joinpath(dir, rel)
        dst=joinpath(target, rel)
        isfile(dst) ? (read(src)==read(dst)||error("拒绝覆盖不同摘要")) :
        (mkpath(dirname(dst)); cp(src, dst))
    end
end
println("R4 discrete scope, verdicts, figure data and portable hashes checked.")
