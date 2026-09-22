module R9CommonEvidence
using TOML, SHA
hashfile(p) = bytes2hex(sha256(read(p)))
function files(root)
    sort([
        replace(relpath(joinpath(d, n), root), '\\'=>'/') for (d, _, ns) in walkdir(root) for
        n in ns
    ])
end
toml(p, d) = open(io->TOML.print(io, d; sorted = true), p, "w")
function safe(root, rel)
    !isabspath(rel) &&
    !occursin(':', rel) &&
    !occursin('\\', rel) &&
    all(x->!(x in ("", ".", "..")), split(rel, '/')) || error("Unsafe evidence path")
    p=abspath(root)
    for part in split(rel, '/')
        p=joinpath(p, part)
        islink(p) && error("Symlink in evidence")
    end
    p
end
function seal(input, run, constructor, out)
    ispath(out) && error("Preserve previous evidence")
    status=TOML.parsefile(joinpath(run, "status.toml"))
    status["status"]=="common_witness_verified" && status["budget_pass"] ||
        error("Not a verified common witness")
    old=TOML.parsefile(joinpath(constructor, "status.toml"))
    status["parent_witness_sha256"]==hashfile(joinpath(constructor, "witness.toml"))==hashfile(
        joinpath(run, "witness.toml"),
    ) || error("Original witness changed")
    mkpath(out)
    cp(run, joinpath(out, "run"))
    toml(joinpath(out, "construction-status.toml"), old)
    toml(
        joinpath(out, "construction-failure.toml"),
        Dict(
            "status"=>old["status"],
            "message"=>first(split(read(joinpath(constructor, "failure.txt"), String), '\n')),
            "original_failure_sha256"=>hashfile(joinpath(constructor, "failure.txt")),
            "raw_stack_retained_locally"=>true,
            "witness_reoptimized"=>false,
        ),
    )
    cp(@__FILE__, joinpath(out, "audit-source.jl"))
    m=Dict(
        "schema"=>"r9-common-evidence-v1",
        "origin"=>"synthetic",
        "input_manifest_sha256"=>hashfile(joinpath(input, "manifest.toml")),
        "files"=>Dict(rel=>hashfile(safe(out, rel)) for rel in files(out)),
    )
    toml(joinpath(out, "delivery.toml"), m)
    hashfile(@__FILE__)==m["files"]["audit-source.jl"] || error("Seal helper changed")
end
function check(input, out; replay = true)
    m=TOML.parsefile(joinpath(out, "delivery.toml"))
    m["schema"]=="r9-common-evidence-v1" && m["origin"]=="synthetic" || error("Evidence scope")
    Set(files(out))==union(Set(keys(m["files"])), Set(["delivery.toml"])) ||
        error("Evidence inventory")
    for (rel, h) in m["files"]
        p=safe(out, rel)
        hashfile(p)==h || error("Changed evidence: $rel")
        filesize(p)<=5*1024^2 || error("Artifact too large")
        occursin(r"(?<![A-Za-z])[A-Za-z]:[/\\]", read(p, String)) &&
            error("Host path in public evidence")
    end
    m["input_manifest_sha256"]==hashfile(joinpath(input, "manifest.toml")) ||
        error("Wrong frozen input")
    status=TOML.parsefile(joinpath(out, "run/status.toml"))
    status["status"]=="common_witness_verified" &&
    status["has_common_candidate"] &&
    status["budget_pass"] &&
    status["elapsed_sec"]<=status["complete_budget_sec"]==600.0 ||
        error("False completion or budget status")
    !status["new_optimization_performed"] &&
    status["parent_witness_sha256"]==hashfile(joinpath(out, "run/witness.toml")) ||
        error("Parent values changed")
    Set(keys(status["schemes"]))==Set(["3A", "3B", "3C"]) || error("Missing scheme")
    for scheme in ("3A", "3B", "3C")
        v=TOML.parsefile(joinpath(out, "run/validation-"*scheme*".toml"))
        s=status["schemes"][scheme]
        all(s[k]==v[k]==true for k in ("model_pass", "risk_pass", "cost_pass")) ||
            error("False scheme status")
        v["scenarios_checked"]==100 &&
        length(v["scenarios"])==100 &&
        !v["original_risk_optimality_claim"] &&
        !v["optimality_pass"] &&
        !v["valid_bound"] || error("Scientific boundary changed")
        s["case_sha256"]==v["case_sha256"] || error("Scheme input identity")
    end
    if replay
        wrapper=Module(gensym(:R9CommonReplay))
        Base.include(wrapper, joinpath(input, "implementation/scripts/r9_reserve_witness.jl"))
        Base.invokelatest() do
            lib=getfield(wrapper, :R9CommonRun)
            getfield(lib, :check)(abspath(input), abspath(joinpath(out, "run")))
        end
    end
    println("Common evidence file/status boundaries passed; numerical replay=", replay)
    true
end
function main(args)
    if length(args)==5 && args[1]=="seal"
        seal(abspath.(args[2:5])...)
    elseif length(args)==3 && args[1]=="check"
        check(abspath.(args[2:3])...)
    else
        error("usage: seal INPUT RUN ORIGINAL_RUN NEW_EVIDENCE | check INPUT EVIDENCE")
    end
end
end
if abspath(PROGRAM_FILE)==@__FILE__
    R9CommonEvidence.main(ARGS)
end
