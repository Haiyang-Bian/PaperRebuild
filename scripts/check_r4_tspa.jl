using PaperRebuild, TOML, SHA, CSV
include("r4_tspa_docs.jl")
sync_r4_tspa(; check = !("--sync" in ARGS))
args=filter(x->!startswith(x, "--"), ARGS)
isempty(args) && exit()
length(args)==1 || error("提供一个报告目录")
dir=only(args)
root=normpath(joinpath(@__DIR__, ".."))
records=TOML.parsefile(joinpath(dir, "evidence.toml"))["records"]
length(records)==8 || error("冻结清单须有8项流程")
for r in records
    r["validation"]["record_pass"] || error("记录不一致")
    e=r["economics"]
    first=e["stage1"]
    validate_r4_allocation(first)==first["validation"] || error("第一阶段分配不一致")
    for x in e["stage2"]
        a=x["allocation"]
        validate_r4_allocation(a)==x["validation"] || error("第二阶段分配不一致")
        abs(a["surplus"]-x["resource_surplus"]-x["included_penalty"])<=1e-6*max(
            1,
            abs(a["surplus"]),
        ) || error("罚项恒等式不成立")
    end
end
for (file, script) in (
    ("report.toml", "report_r4_tspa.jl"),
    ("figure-config.toml", "plot_r4_tspa.jl"),
    ("audit.toml", "audit_r4_tspa.jl"),
)
    TOML.parsefile(joinpath(dir, file))["script_sha256"]==bytes2hex(
        sha256(read(joinpath(root, "scripts", script))),
    ) || error("生成脚本变化")
end
length(collect(CSV.File(joinpath(dir, "solver-evidence.csv"))))==24 || error("阶段求解器证据缺失")
cutset=collect(CSV.File(joinpath(dir, "network-necessary-condition.csv")))
length(cutset)==32 || error("逐时必要条件缺失")
for row in cutset
    abs(row.cutset_violation_MW-max(-row.required_H12_out_MW, 0))<=1e-12 ||
        error("区域守恒证明不一致")
end
for (file, hash) in TOML.parsefile(joinpath(dir, "figure-config.toml"))["source_sha256"]
    bytes2hex(sha256(read(joinpath(dir, file))))==hash || error("图源改变")
end
hashes=Dict{String,String}()
for (folder, _, files) in walkdir(dir), file in files
    file=="artifact-hashes.toml" && continue
    path=joinpath(folder, file)
    stat(path).size<=5*1024^2 || error("摘要文件过大")
    if endswith(file, ".toml") || endswith(file, ".csv")
        occursin(r"(?i)[A-Z]:[\\/]|/Users/|/home/", read(path, String)) && error("本机路径泄漏")
    end
    hashes[replace(relpath(path, dir), '\\'=>'/')]=bytes2hex(sha256(read(path)))
end
manifest=joinpath(dir, "artifact-hashes.toml")
if "--seal" in ARGS
    isfile(manifest) && error("不重封原报告")
    write(manifest, PaperRebuild.r4_text(Dict("sha256"=>hashes)))
else
    TOML.parsefile(manifest)["sha256"]==hashes || error("摘要文件变化")
end
if "--publish" in ARGS
    target=joinpath(root, "docs", "src", "assets", "r4-tspa")
    for rel in vcat(collect(keys(hashes)), ["artifact-hashes.toml"])
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
println("R4 TSPA accounting, source hashes and portable artifacts checked.")
