# 原字节分片封存/重读无备用开发探针。复用既有4MiB对象池，不重算科研结果。
using TOML, SHA
length(ARGS) in (2, 3) && ARGS[1] in ("seal", "check") ||
    error("usage: seal_r9_reserve_probe.jl seal PROBE NEW_SUMMARY | check SUMMARY")
files(root) = sort([
    replace(relpath(joinpath(d, f), root), '\\'=>'/') for (d, _, names) in walkdir(root) for
    f in names
])
hashfile(p) = bytes2hex(sha256(read(p)))
write_toml(p, d) = open(io->TOML.print(io, d; sorted = true), p, "w")
seal=ARGS[1]=="seal"
if seal
    length(ARGS)==3 || error("seal needs source and destination")
    source, destination=abspath.(ARGS[2:3])
    ispath(destination) && error("Do not overwrite previous evidence")
    status=TOML.parsefile(joinpath(source, "probe-status.toml"))
    !status["formal_risk_experiment"] && status["budget_pass"] || error("Probe boundary changed")
    include(joinpath(@__DIR__, "r9_fixed_evidence.jl"))
    mkpath(joinpath(destination, "objects"))
    mkpath(joinpath(destination, "archive-code"))
    source_files=R9FixedEvidence.pack(destination, source)
    cp(@__FILE__, joinpath(destination, "audit-source.jl"))
    cp(
        joinpath(@__DIR__, "r9_fixed_evidence.jl"),
        joinpath(destination, "archive-code", "r9_fixed_evidence.jl"),
    )
    manifest=Dict(
        "schema"=>"r9-reserve-probe-seal-v2",
        "origin"=>"synthetic",
        "formal_risk_experiment"=>false,
        "solver_used_for_replay"=>false,
        "source_files"=>source_files,
        "files"=>Dict(
            rel=>hashfile(joinpath(destination, split(rel, '/')...)) for rel in files(destination)
        ),
    )
    write_toml(joinpath(destination, "delivery.toml"), manifest)
else
    length(ARGS)==2 || error("check needs one summary")
    destination=abspath(ARGS[2])
    include(joinpath(destination, "archive-code", "r9_fixed_evidence.jl"))
end
manifest=TOML.parsefile(joinpath(destination, "delivery.toml"))
manifest["schema"]=="r9-reserve-probe-seal-v2" &&
manifest["origin"]=="synthetic" &&
!manifest["formal_risk_experiment"] &&
!manifest["solver_used_for_replay"] || error("Delivery scope changed")
observed=filter(!=("delivery.toml"), files(destination))
observed==sort(collect(keys(manifest["files"]))) || error("Delivery inventory changed")
for rel in observed
    path=joinpath(destination, split(rel, '/')...)
    hashfile(path)==manifest["files"][rel] || error("Changed evidence: $rel")
    filesize(path)<=5*1024^2 || error("Artifact exceeds 5MiB: $rel")
end
mktempdir() do unpacked
    for (rel, hash) in manifest["source_files"]
        !isabspath(rel) &&
        !occursin(':', rel) &&
        !occursin('\\', rel) &&
        all(p->!(p in ("", ".", "..")), split(rel, '/')) || error("Unsafe original path")
        content=R9FixedEvidence.bytes(destination, hash)
        # 分片可能位于UTF8字符中间；只在重组完整原字节后检查可移植文本。
        occursin(r"(?<![A-Za-z])[A-Za-z]:[/\\]", String(copy(content))) &&
            error("Nonportable original path: $rel")
        path=joinpath(unpacked, split(rel, '/')...)
        mkpath(dirname(path))
        write(path, content)
    end
    inputhashes=TOML.parsefile(joinpath(unpacked, "input-hashes.toml"))
    for (rel, h) in inputhashes
        hashfile(joinpath(unpacked, "input-code", split(rel, '/')...))==h ||
            error("Input source changed")
    end
    Base.include(Main, joinpath(unpacked, "run", "code", "replay.jl"))
    record=Base.invokelatest() do
        library=getfield(Main, :FrozenR5Commitment)
        getfield(library, :read_r5_commitment_run)(joinpath(unpacked, "run"))
    end
    status=TOML.parsefile(joinpath(unpacked, "probe-status.toml"))
    for k in ("model_pass", "kkt_pass")
        status[k]==record.validation[k] || error("Probe result changed")
    end
    status["case_sha256"]==record.case.sha256 || error("Input identity changed")
    println(
        "Frozen nominal probe passed: ",
        length(observed),
        " shards/files, ",
        length(manifest["source_files"]),
        " original files; not a risk experiment.",
    )
end
