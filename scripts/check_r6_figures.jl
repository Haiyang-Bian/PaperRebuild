using CSV, TOML, SHA

"""核对R6图源、原统计和图文件身份；可显式复制同字节图件到新文档资产目录，不求解。"""
function check_r6_figures(public, figures; docs_assets = nothing)
    hashfile(p) = bytes2hex(sha256(read(p)))
    p=TOML.parsefile(joinpath(public, "public.toml"))
    hashfile(joinpath(public, "public.toml"))==strip(
        read(joinpath(public, "public.sha256"), String),
    ) || error("公开包清单改变")
    c=TOML.parsefile(joinpath(figures, "figure-config.toml"))
    c["schema"]=="r6-study-figures-v1" &&
    c["origin"]==p["origin"]=="synthetic" &&
    c["solver_reexecuted"]===false || error("图表证据类型不同")
    c["public_evidence_sha256"]==hashfile(joinpath(public, "public.toml")) || error("图表来源不同")
    c["batch_id"]==p["batch_id"] || error("批次不同")
    c["risk_bounds"]=="separate_one_sided_95_percent_not_simultaneous" &&
    c["paired_interval"]=="individual_percentile_bootstrap_95_percent" || error("统计范围不同")
    hashfile(joinpath(figures, "plot_r6_study.jl"))==c["script_sha256"] || error("图源程序改变")
    for (folder, entries) in
        ((public, p["files"]), (figures, c["sources"]), (figures, c["figures"]))
        for (rel, h) in entries
            !isabspath(rel) &&
            !occursin(':', rel) &&
            !occursin('\\', rel) &&
            all(x->!(x in ("", ".", "..")), split(rel, '/')) || error("图表路径非法")
            hashfile(joinpath(folder, split(rel, '/')...))==h || error("文件改变：$rel")
        end
    end
    report=TOML.parsefile(joinpath(public, "tables/report.toml"))
    readtable(path) = collect(CSV.File(read(path)))
    days=reduce(
        vcat,
        [
            readtable(joinpath(public, "tables", f)) for
            f in sort(collect(keys(report["tables"]))) if startswith(f, "days")
        ],
    )
    tests=filter(r->r.split=="test", days)
    risk=filter(r->r.split=="test", readtable(joinpath(public, "tables/risk-cost.csv")))
    hourly=readtable(joinpath(public, "hourly.csv"))
    expected=Dict(
        "test-costs.csv"=>tests,
        "risk.csv"=>risk,
        "paired-cost.csv"=>readtable(joinpath(public, "tables/paired-cost.csv")),
        "hourly.csv"=>hourly,
        "temperatures.csv"=>readtable(joinpath(public, "temperatures.csv")),
    )
    Set(keys(expected))==Set(keys(c["sources"])) || error("图源清单不同")
    for (name, rows) in expected
        io=IOBuffer()
        CSV.write(io, rows)
        take!(io)==read(joinpath(figures, name)) || error("图源未忠实读取原值：$name")
    end
    sort(unique(String(x.run_id) for x in vcat(tests, hourly)))==c["run_ids"] || error("运行ID缺失")
    names=[f*"."*ext for f in ("F17", "F18", "F19") for ext in ("png", "pdf")]
    Set(names)==Set(keys(c["figures"])) || error("图件不完整")
    if docs_assets!==nothing
        # 只新增或验证相同字节，不覆盖另一轮文档资产。
        mkpath(docs_assets)
        for name in vcat(names, ["figure-config.toml"])
            source, target=joinpath(figures, name), joinpath(docs_assets, name)
            ispath(target) ? (hashfile(target)==hashfile(source) || error("已有文档图不同")) :
            cp(source, target)
        end
    end
    println(
        "R6 F17/F18/F19 data, scope, run IDs and PNG/PDF hashes checked; layout requires visual review.",
    )
end

if abspath(PROGRAM_FILE)==@__FILE__
    length(ARGS) in (2, 3) ||
        error("usage: check_r6_figures.jl <public> <figures> [new-doc-assets]")
    check_r6_figures(ARGS[1], ARGS[2]; docs_assets = length(ARGS)==3 ? ARGS[3] : nothing)
end
