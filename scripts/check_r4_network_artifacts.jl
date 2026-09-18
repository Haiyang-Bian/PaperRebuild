using PaperRebuild, TOML, CSV, SHA
args=filter(x->!startswith(x, "--"), ARGS)
length(args)==1 || error("参数：报告目录 [--seal] [--publish]")
dir=only(args);
root=normpath(joinpath(@__DIR__, ".."))
meta=TOML.parsefile(joinpath(dir, "report.toml"))
config=joinpath(root, "configs", "r4", "reconfiguration", "study.toml")
meta["config_sha256"]==bytes2hex(sha256(read(config))) || error("输入规则改变")
meta["script_sha256"]==bytes2hex(
    sha256(read(joinpath(@__DIR__, "report_r4_reconfiguration.jl"))),
) || error("报告程序改变")
rows=collect(CSV.File(joinpath(dir, "comparison.csv")))
length(rows)==34&&length(unique(x.run_id for x in rows))==34 || error("34项整数清单不完整")
oracle=collect(CSV.File(joinpath(dir, "oracle.csv")))
length(oracle)==72 && [x.index for x in oracle]==collect(1:72) || error("枚举清单缺失")
rules=TOML.parsefile(config)
for x in rows
    x.input_sha256==rules["input_sha256"][x.case] || error("输入不匹配")
    x.original_electric_A1&&!x.model_A1 && error("物理标志不一致")
    x.certificate_A2&&!(x.model_A1&&isfinite(x.relative_gap)&&x.relative_gap<=1e-4) &&
        error("费用证书错误")
    isfinite(x.cost)&&abs(
            x.cost-x.resource_cost-x.discomfort_cost-x.external_cost-x.switching_cost,
        )>1e-5 &&
        error("费用分项不闭合")
end
checks=TOML.parsefile(joinpath(dir, "checks.toml"))
checks["model_pass_count"]==count(x->x.model_A1, rows) || error("模型通过数不符")
checks["original_pass_count"]==count(x->x.original_electric_A1, rows) || error("电网通过数不符")
diag=collect(CSV.File(joinpath(dir, "thermal-diagnostic.csv")))
checks["heat_mass_screen_count"]==count(x->x.positive_heat_near_zero_mass, diag) ||
    error("热诊断遗漏")
fig=TOML.parsefile(joinpath(dir, "figure-config.toml"))
!fig["solver_reexecuted"] || error("绘图不应重新求解")
fig["script_sha256"]==bytes2hex(sha256(read(joinpath(@__DIR__, "plot_r4_reconfiguration.jl")))) ||
    error("绘图脚本变化")
for (f, h) in fig["sources"]
    bytes2hex(sha256(read(joinpath(dir, f))))==h || error("图源变化")
end
hashes=Dict{String,String}()
for (folder, _, files) in walkdir(dir), file in files
    file=="artifact-hashes.toml"&&continue
    path=joinpath(folder, file)
    stat(path).size<=5*1024^2 || error("摘要单文件过大")
    if endswith(file, ".toml")||endswith(file, ".csv")
        occursin(r"(?i)[A-Z]:[\\/]|/Users/|/home/", read(path, String))&&error("本机路径")
    end
    hashes[replace(relpath(path, dir), '\\'=>'/')]=bytes2hex(sha256(read(path)))
end
manifest=joinpath(dir, "artifact-hashes.toml")
if "--seal" in ARGS
    ispath(manifest)&&error("拒绝重新封存")
    write(manifest, PaperRebuild.r4_text(Dict("sha256"=>hashes)))
else
    TOML.parsefile(manifest)["sha256"]==hashes || error("摘要文件或哈希改变")
end
if "--publish" in ARGS
    target=joinpath(root, "docs", "src", "assets", "r4-network")
    for rel in vcat(collect(keys(hashes)), ["artifact-hashes.toml"])
        src=joinpath(dir, rel)
        dst=joinpath(target, rel)
        if isfile(dst)
            read(src)==read(dst) || error("不覆盖不同的已发布摘要")
        else
            mkpath(dirname(dst))
            cp(src, dst)
        end
    end
end
println("R4 network evidence, cost accounting, diagnostics and portable figure hashes checked.")
