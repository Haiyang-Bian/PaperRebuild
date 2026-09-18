using PaperRebuild, TOML, CSV, SHA
args=filter(x->!startswith(x, "--"), ARGS)
length(args)==1 || error("参数：报告目录 [--seal] [--publish]")
dir=only(args)
root=normpath(joinpath(@__DIR__, ".."))
meta=TOML.parsefile(joinpath(dir, "report.toml"))
rules=TOML.parsefile(joinpath(root, "configs", "r4", "heat-compatibility-study.toml"))
meta["config_sha256"]==bytes2hex(
    sha256(read(joinpath(root, "configs", "r4", "heat-compatibility-study.toml"))),
)||error("规则变化")
meta["script_sha256"]==bytes2hex(
    sha256(read(joinpath(@__DIR__, "report_r4_heat_compatibility.jl"))),
)||error("报告程序变化")
rows=collect(CSV.File(joinpath(dir, "comparison.csv")))
expected=Set(
    x["id"]*"--"*b["id"]*"--"*s for x in rules["records"], b in rules["bands"], s in rules["stages"]
)
length(rows)==length(expected)&&Set(x.run_id for x in rows)==expected||error("272项阶段清单不闭合")
for x in rows
    x.pass&&!(x.saved&&x.independent_checked&&x.status=="compatible_candidate")&&error(
        "通过判定不一致",
    )
    x.detailed_temperature_pass!=(endswith(x.stage, "mixing")&&x.pass)&&error(
        "必要条件误作详细通过",
    )
    x.saved&&x.cost_change!=0&&error("费用不应变化")
    x.parent_electric_A1&&!x.parent_model_A1&&error("父判定不一致")
    x.pass&&x.max_normalized_residual>1&&error("超过A1")
end
counts=collect(CSV.File(joinpath(dir, "counts.csv")))
length(counts)==8||error("阶段统计不完整")
for x in counts
    rr=filter(y->y.band==x.band&&y.stage==x.stage, rows)
    x.required==length(rr)&&x.saved==count(y->y.saved, rr)&&x.pass==count(y->y.pass, rr)||error(
        "统计失配",
    )
end
checks=TOML.parsefile(joinpath(dir, "checks.toml"))
residuals=vcat(
    [
        collect(CSV.File(joinpath(dir, "residuals-"*b*".csv"))) for
        b in ("reference10", "reference20")
    ]...,
)
length(residuals)==checks["residual_row_count"]||error("残差分片不完整")
maxima=Dict{String,Float64}()
passes=Dict{String,Bool}()
for x in residuals
    x.pass==(x.residual<=x.tolerance)||error("残差判定错误")
    isapprox(x.normalized, x.residual/x.tolerance; atol = 0, rtol = 1e-12)||error("残差归一化错误")
    id=String(x.run_id)
    maxima[id]=max(get(maxima, id, 0.0), x.normalized)
    passes[id]=get(passes, id, true)&&x.pass
end
for x in rows
    x.independent_checked||continue
    maxima[x.run_id]==x.max_normalized_residual&&passes[x.run_id]==x.pass||error(
        "残差与阶段摘要失配",
    )
end
checks["required_stage_count"]==length(rows)&&checks["saved_stage_count"]==count(x->x.saved, rows)||error(
    "数量不匹配",
)
checks["detailed_free_pass_count"]==count(x->x.stage=="free_mixing"&&x.pass, rows)||error(
    "自由流温度计数",
)
checks["detailed_fixed_pass_count"]==count(x->x.stage=="fixed_mixing"&&x.pass, rows)||error(
    "固定流温度计数",
)
checks["unchanged_controls_and_cost"]&&!checks["pressure_dynamics_actual_temperature_loss_checked"]||error(
    "研究边界改变",
)
fig=TOML.parsefile(joinpath(dir, "figure-config.toml"))
!fig["solver_reexecuted"]||error("重绘不得求解")
fig["script_sha256"]==bytes2hex(sha256(read(joinpath(@__DIR__, "plot_r4_heat_compatibility.jl"))))||error(
    "绘图程序变化",
)
for (f, h) in fig["sources"]
    bytes2hex(sha256(read(joinpath(dir, f))))==h||error("图源变化")
end
hashes=Dict{String,String}()
for (folder, _, files) in walkdir(dir), file in files
    file=="artifact-hashes.toml"&&continue
    path=joinpath(folder, file)
    stat(path).size<=5*1024^2||error("摘要单文件过大")
    if endswith(file, ".toml")||endswith(file, ".csv")
        occursin(r"(?i)[A-Z]:[\\/]|/Users/|/home/", read(path, String))&&error("本机绝对路径")
    end
    hashes[replace(relpath(path, dir), '\\'=>'/')]=bytes2hex(sha256(read(path)))
end
manifest=joinpath(dir, "artifact-hashes.toml")
if "--seal" in ARGS
    ispath(manifest)&&error("拒绝重复封存")
    write(manifest, PaperRebuild.r4_text(Dict("sha256"=>hashes)))
else
    TOML.parsefile(manifest)["sha256"]==hashes||error("摘要变更")
end
if "--publish" in ARGS
    target=joinpath(root, "docs", "src", "assets", "r4-heat")
    for rel in vcat(collect(keys(hashes)), ["artifact-hashes.toml"])
        src=joinpath(dir, rel)
        dst=joinpath(target, rel)
        if isfile(dst)
            read(src)==read(dst)||error("不覆盖不同的已有文档数据")
        else
            mkpath(dirname(dst))
            cp(src, dst)
        end
    end
end
println(
    "R4 heat evidence: complete stage coverage, frozen costs and portable artifact hashes checked.",
)
