module R9SeededEvidence
using TOML, SHA
hashfile(p) = bytes2hex(sha256(read(p)))
files(root) = sort([
    replace(relpath(joinpath(d, n), root), '\\'=>'/') for (d, _, ns) in walkdir(root) for n in ns
])
toml(p, x) = open(io->TOML.print(io, x; sorted = true), p, "w")
function safe(root, rel)
    !isabspath(rel) &&
    !occursin(':', rel) &&
    !occursin('\\', rel) &&
    all(x->x ∉ ("", ".", ".."), split(rel, '/')) || error("Unsafe relative path")
    p=abspath(root)
    for part in split(rel, '/')
        p=joinpath(p, part)
        islink(p) && error("Symlink in evidence")
    end
    p
end

"""封存新运行的原数值；本地完整日志仅记录哈希，不公开机器路径。"""
function seal(common, frozen, runs, out)
    ispath(out) && error("Preserve old evidence")
    mkpath(out)
    manifest=TOML.parsefile(joinpath(frozen, "manifest.toml"))
    for scheme in manifest["protocol"]["schemes"]
        src=joinpath(runs, scheme)
        dst=joinpath(out, scheme)
        mkpath(dst)
        cp(joinpath(src, "status.toml"), joinpath(dst, "status.toml"))
        isdir(joinpath(src, "run")) && cp(joinpath(src, "run"), joinpath(dst, "run"))
        logs=Dict{String,Any}()
        for name in ("solver.log", "failure.txt")
            p=joinpath(src, name)
            if isfile(p)
                logs[name]=Dict(
                    "sha256"=>hashfile(p),
                    "bytes"=>filesize(p),
                    "retained_locally"=>true,
                )
                if name=="failure.txt"
                    msg=first(split(read(p, String), '\n'))
                    occursin(r"[A-Za-z]:[/\\]", msg) || (logs[name]["first_line"]=msg)
                end
            end
        end
        toml(joinpath(dst, "local-logs.toml"), logs)
    end
    cp(@__FILE__, joinpath(out, "audit-source.jl"))
    m=Dict(
        "schema"=>"r9-seeded-evidence-v1",
        "origin"=>"synthetic",
        "common_sha256"=>hashfile(joinpath(common, "manifest.toml")),
        "freeze_sha256"=>hashfile(joinpath(frozen, "manifest.toml")),
        "files"=>Dict(p=>hashfile(safe(out, p)) for p in files(out)),
    )
    toml(joinpath(out, "delivery.toml"), m)
    check(common, frozen, out; replay = false)
end

"""核对阶段状态、预算及完成标志；可选从冻结验证器重算全部原情景数值，无新优化。"""
function check(common, frozen, out; replay = true)
    m=TOML.parsefile(joinpath(out, "delivery.toml"))
    m["schema"]=="r9-seeded-evidence-v1" && m["origin"]=="synthetic" || error("Evidence schema")
    m["common_sha256"]==hashfile(joinpath(common, "manifest.toml")) || error("Common input changed")
    m["freeze_sha256"]==hashfile(joinpath(frozen, "manifest.toml")) || error("Seeded input changed")
    Set(files(out))==union(Set(keys(m["files"])), Set(["delivery.toml"])) ||
        error("Evidence inventory")
    for (p, h) in m["files"]
        f=safe(out, p)
        hashfile(f)==h && filesize(f)<=5*1024^2 || error("Evidence changed or too large")
        occursin(r"(?<![A-Za-z])[A-Za-z]:[/\\]", read(f, String)) && error("Host path in evidence")
    end
    fm=TOML.parsefile(joinpath(frozen, "manifest.toml"))
    for scheme in fm["protocol"]["schemes"]
        dir=joinpath(out, scheme)
        s=TOML.parsefile(joinpath(dir, "status.toml"))
        s["scheme"]==scheme && s["origin"]=="synthetic" || error("Run scope")
        s["freeze_sha256"]==m["freeze_sha256"] || error("Run source changed")
        s["budget_sec"]==600.0 &&
        s["elapsed_sec"]>=0 &&
        s["budget_pass"]==(s["elapsed_sec"]<=600.0) || error("False budget status")
        if !isdir(joinpath(dir, "run"))
            s["status"] in ("execution_error", "license_unavailable") &&
            !get(s, "model_pass", false) || error("Missing numerical result")
            continue
        end
        r=TOML.parsefile(joinpath(dir, "run/result.toml"))
        v=TOML.parsefile(joinpath(dir, "run/validation.toml"))
        s["case_sha256"]==r["case_sha256"]==fm["cases"][scheme] || error("Case identity")
        s["parent_witness_sha256"]==fm["protocol"]["parent_witness_sha256"] || error("Wrong seed")
        s["status"]==r["status"] && s["has_candidate"]==r["has_candidate"] ||
            error("False solver status")
        representation=get(fm["protocol"], "representation", "original")
        get(s, "representation", "original")==get(r, "representation", "original")==representation ||
            error("Representation mismatch")
        get(s, "solver_logging_requested", false)==get(r, "solver_logging_requested", false)==get(
            fm["protocol"],
            "solver_log",
            false,
        ) || error("Logging mismatch")
        if representation=="r9_compact_v1"
            get(r, "representation_source_hashes", Dict())==Dict(
                p=>fm["source_hashes"][p] for
                p in ("src/formulations/r9_compact_risk.jl", "src/algorithms/r9_compact_risk.jl")
            ) || error("Compact source mismatch")
        end
        for key in ("model_pass", "risk_pass", "cost_pass", "optimality_pass")
            s[key]==v[key] || error("False validation flag")
        end
        expected=r["status"]=="solver_optimal" && v["optimality_pass"] && r["elapsed_sec"]<=600.0
        s["cost_optimization_complete"]==r["cost_optimization_complete"]==expected ||
            error("False completion flag")
        if r["has_candidate"]
            haskey(r, "first_stage") && isfile(joinpath(dir, "run/scenario-001.toml")) ||
                error("Missing solver values")
        else
            !haskey(r, "first_stage") && !v["model_pass"] || error("Hidden seed fallback")
        end
        if replay
            wrapper=Module(gensym(:SeededReplay))
            Base.include(wrapper, joinpath(frozen, "implementation/scripts/r9_seeded_study.jl"))
            Base.invokelatest() do
                getfield(getfield(wrapper, :R9SeededStudy), :check)(common, frozen, scheme, dir)
            end
        end
    end
    println("Seeded evidence scope/status checks passed; full numerical replay=", replay)
    true
end
end
if abspath(PROGRAM_FILE)==@__FILE__
    length(ARGS) in (4, 5) || error(
        "usage: seal COMMON_INPUT FREEZE RUNS NEW_EVIDENCE | check COMMON_INPUT FREEZE EVIDENCE",
    )
    ARGS[1]=="seal" && length(ARGS)==5 ? R9SeededEvidence.seal(abspath.(ARGS[2:5])...) :
    ARGS[1]=="check" && length(ARGS)==4 ? R9SeededEvidence.check(abspath.(ARGS[2:4])...) :
    error("Arguments")
end
