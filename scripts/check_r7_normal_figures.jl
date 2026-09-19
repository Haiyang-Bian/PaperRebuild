using TOML, SHA

function check_r7_normal_figures(bundle, figdir, doc_png = nothing)
    manifest=TOML.parsefile(joinpath(figdir, "files.toml"))["files"]
    actual=Dict(
        replace(relpath(joinpath(p, f), figdir), '\\'=>'/')=>bytes2hex(
            sha256(read(joinpath(p, f))),
        ) for (p, _, files) in walkdir(figdir) for
        f in files if joinpath(p, f)!=joinpath(figdir, "files.toml")
    )
    actual==manifest || error("科学图文件被改变")
    config=TOML.parsefile(joinpath(figdir, "figure.toml"))
    summary=TOML.parsefile(joinpath(bundle, "summary.toml"))
    event=TOML.parsefile(joinpath(bundle, "event", "event.toml"))
    config["normal_run_id"]==summary["normal_run_id"] &&
    config["event_run_ids"]==[r["run_id"] for r in event["records"]] || error("图中运行身份不一致")
    config["evidence_manifest_sha256"]==bytes2hex(
        sha256(read(joinpath(bundle, "evidence-files.toml"))),
    ) || error("图源报告身份改变")
    config["origin"]=="synthetic" && config["units"]==["h", "MW", "MWh", "USD"] ||
        error("合成范围或单位错误")
    for file in ("normal-trajectory.csv", "event-summary.csv")
        read(joinpath(bundle, file))==read(joinpath(figdir, file)) ||
            error("科学图源数据不来自已核验报告")
    end
    if !isnothing(doc_png)
        read(doc_png)==read(joinpath(figdir, "F20-normal-event.png")) ||
            error("文档图片与已核验图不一致")
    end
    println("R7 F20 figure source, run IDs, units and hashes checked; no optimization")
    true
end

if abspath(PROGRAM_FILE)==(@__FILE__)
    length(ARGS) in (2, 3) || error("check_r7_normal_figures.jl BUNDLE FIGURE_DIR [DOC_PNG]")
    check_r7_normal_figures(ARGS...)
end
