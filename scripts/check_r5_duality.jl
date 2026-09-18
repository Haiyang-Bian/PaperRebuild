using PaperRebuild, TOML, CSV, SHA
include("r5_duality_docs.jl")
"--sync" in ARGS&&sync_r5_duality_docs()
root=normpath(joinpath(@__DIR__, ".."))
ledger=TOML.parsefile(joinpath(root, "docs", "reading", "ch05", "recourse-duality.toml"))
page=read(joinpath(root, "docs", "src", "ch05-recourse-equations.md"), String)
api=read(joinpath(root, "docs", "src", "api.md"), String)
tests=read(joinpath(root, "test", "r5_dispatch_duality.jl"), String)
for x in ledger["equation"]
    occursin("\\tag{"*x["id"]*"}", page)&&occursin(x["test"], tests)||error("对偶公式/测试缺失")
    Base.Docs.hasdoc(PaperRebuild, Symbol(x["api"]))&&occursin("PaperRebuild."*x["api"], api)||error(
        "对偶API缺失",
    )
end
args=filter(x->!startswith(x, "--"), ARGS)
if !isempty(args)
    dir=only(args)
    meta=TOML.parsefile(joinpath(dir, "audit.toml"))
    meta["schema"]=="r5-dispatch-duality-audit-v1"&&!meta["solver_reexecuted"]||error(
        "审计身份不符",
    )
    bytes2hex(sha256(read(joinpath(@__DIR__, "audit_r5_dispatch_duality.jl"))))==meta["script_sha256"]||error(
        "审计入口改变",
    )
    for (rel, hash) in meta["source_sha256"]
        bytes2hex(sha256(read(joinpath(root, split(rel, '/')...))))==hash||error(
            "审计源码改变：$rel",
        )
    end
    summary=collect(CSV.File(joinpath(dir, "comparison.csv")))
    residuals=collect(CSV.File(joinpath(dir, "kkt-residuals.csv")))
    sensitivities=collect(CSV.File(joinpath(dir, "sensitivity.csv")))
    parent=TOML.parsefile(joinpath(root, "results", "summaries", "r5-dispatch", "report.toml"))
    meta["parent_study_sha256"]==parent["study_sha256"]&&meta["parent_config_sha256"]==parent["config_sha256"]||error(
        "父批次不同",
    )
    Set(x.record_id for x in summary)==Set(keys(parent["raw_source_hashes"]))&&length(summary)==meta["records"]==24||error(
        "运行范围不同",
    )
    for row in summary
        file="witnesses/"*row.record_id*".toml"
        path=joinpath(dir, split(file, '/')...)
        bytes2hex(sha256(read(path)))==meta["witness_sha256"][file]||error("对偶见证改变")
        witness=TOML.parsefile(path)
        witness["parent_result_sha256"]==parent["raw_source_hashes"][row.record_id]||error(
            "父原值不同",
        )
        c=R5DispatchCase(witness["case"])
        r=witness["result"]
        c.sha256==row.case_sha256&&r["run_id"]==row.run_id||error("见证身份错误")
        k=validate_r5_dispatch_duals(c, r)
        k["kkt_pass"]==row.kkt_pass&&k["status"]==row.audit_status||error("原始对偶判定改变")
        rr=filter(x->x.record_id==row.record_id, residuals)
        length(rr)==length(k["rows"])||error("残差行缺失")
        for (old, new) in zip(rr, k["rows"])
            old.id==new["id"]&&old.kind==new["kind"]&&old.pass==new["pass"]&&isapprox(
                old.residual,
                new["residual"];
                atol = 1e-14,
                rtol = 1e-12,
            )||error("独立KKT残差不同")
        end
        ss=filter(x->x.record_id==row.record_id, sensitivities)
        if k["kkt_pass"]
            a=r5_dispatch_sensitivity(c, r; objective = :total)
            b=r5_dispatch_sensitivity(c, r)
            length(ss)==3c.data["T"]||error("灵敏度范围不完整")
            for x in ss
                isapprox(x.total_USD_per_MW, a["gradient"][x.parameter][x.t]; atol = 1e-10)&&isapprox(
                    x.recourse_USD_per_MW,
                    b["gradient"][x.parameter][x.t];
                    atol = 1e-10,
                )||error("次梯度不同")
            end
        else
            isempty(ss)||error("不可信对偶生成梯度")
        end
    end
    count(x->x.kkt_pass, summary)==meta["kkt_pass"]||error("汇总不同")
    fig=TOML.parsefile(joinpath(dir, "figure-config.toml"))
    !fig["solver_reexecuted"]&&Set(fig["source_run_ids"])==Set(x.run_id for x in summary)||error(
        "对偶图源错误",
    )
    bytes2hex(sha256(read(joinpath(@__DIR__, "plot_r5_duality.jl"))))==fig["script_sha256"]||error(
        "对偶绘图脚本改变",
    )
    for (file, hash) in fig["sources"]
        bytes2hex(sha256(read(joinpath(dir, file))))==hash||error("对偶绘图输入改变")
    end
    hashes=Dict{String,String}()
    for (base, _, files) in walkdir(dir), file in files
        file=="artifact-hashes.toml"&&continue
        path=joinpath(base, file)
        rel=replace(relpath(path, dir), '\\'=>'/')
        filesize(path)<5*1024^2||error("公开文件过大")
        if endswith(file, ".csv")||endswith(file, ".toml")
            occursin(r"(?i)[A-Z]:[\\/]|/Users/|/home/", read(path, String))&&error("本机路径泄露")
        end
        hashes[rel]=bytes2hex(sha256(read(path)))
    end
    seal=joinpath(dir, "artifact-hashes.toml")
    if "--seal" in ARGS
        ispath(seal)&&error("不覆盖对偶封存")
        write(seal, PaperRebuild.r5_market_text(Dict("sha256"=>hashes)))
    else
        TOML.parsefile(seal)["sha256"]==hashes||error("对偶封存变化")
    end
    if "--publish" in ARGS
        target=joinpath(root, "docs", "src", "assets", "r5-duality")
        for rel in vcat(collect(keys(hashes)), ["artifact-hashes.toml"])
            src=joinpath(dir, split(rel, '/')...)
            dst=joinpath(target, split(rel, '/')...)
            if ispath(dst)
                read(src)==read(dst)||error("不覆盖旧对偶文档证据")
            else
                mkpath(dirname(dst))
                cp(src, dst)
            end
        end
    end
    println(
        "Recourse duality witnesses: ",
        meta["kkt_pass"],
        "/",
        meta["records"],
        "; all raw values and sensitivities replayed.",
    )
end
println("Recourse duality: 5 project equations, 4 symbol groups and 4 adoption boundaries mapped.")
