function r7_transport_science_paths()
    root=normpath(joinpath(@__DIR__, "..", ".."))
    merge(
        r7_thermal_science_paths(),
        Dict(
            "src/$layer/r7_transport.jl"=>joinpath(root, "src", layer, "r7_transport.jl") for
            layer in ("core", "formulations", "verification", "algorithms", "reporting")
        ),
    )
end
r7_transport_science_hashes() =
    Dict(p=>bytes2hex(sha256(read(f))) for (p, f) in r7_transport_science_paths())

"""保存逐管联合恢复的输入、流量/空间状态、原始解、独立验算及源码；拒绝覆盖或求解后源码漂移。"""
function save_r7_transport_recovery(c, s, r, directory::AbstractString)
    r["source_hashes_at_solve"]==r7_transport_science_hashes() || error("逐管求解后源码改变")
    isequal(validate_r7_transport_recovery(c, s, r), r["validation"]) || error("逐管数值与摘要不符")
    dest=abspath(directory)
    ispath(dest)&&error("不覆盖逐管恢复")
    stage=dest*".writing-"*string(uuid4())
    mkpath(stage)
    for (p, o) in (("case.toml", c.data), ("spec.toml", s), ("result.toml", r))
        write(joinpath(stage, p), r7_text(o))
    end
    for (p, f) in r7_transport_science_paths()
        target=joinpath(stage, "code", split(p, '/')...)
        mkpath(dirname(target))
        cp(f, target)
    end
    layers=("core", "formulations", "verification", "algorithms", "reporting")
    replay="module FrozenR7Transport\nusing JuMP,TOML,SHA,Dates,UUIDs\nconst MOI=JuMP.MOI\n" *
           join("include(\"src/$layer/r7_recovery.jl\")\n" for layer in layers) *
           "include(\"src/networks/r7_pipe_state.jl\")\n" *
           join("include(\"src/$layer/r7_thermal.jl\")\n" for layer in layers) *
           join("include(\"src/$layer/r7_transport.jl\")\n" for layer in layers) *
           "end\nx=FrozenR7Transport.read_r7_transport_recovery(joinpath(@__DIR__,\"..\"))\nprintln(x.result[\"status\"],\" model=\",x.validation[\"model_pass\"])\n"
    write(joinpath(stage, "code/replay.jl"), replay)
    files=Dict(
        replace(relpath(joinpath(p, f), stage), '\\'=>'/')=>bytes2hex(sha256(read(joinpath(p, f))))
        for (p, _, fs) in walkdir(stage) for f in fs
    )
    write(joinpath(stage, "files.toml"), r7_text(Dict("files"=>files)))
    mv(stage, dest)
    read_r7_transport_recovery(dest)
    dest
end

"""只读核验逐管恢复原值与哈希；科学源码变化时使用记录自带code/replay.jl，不重新优化。"""
function read_r7_transport_recovery(directory::AbstractString)
    files=TOML.parsefile(joinpath(directory, "files.toml"))["files"]
    required=Set(
        vcat(
            ["case.toml", "spec.toml", "result.toml", "code/replay.jl"],
            ["code/"*p for p in keys(r7_transport_science_paths())],
        ),
    )
    Set(keys(files))==required || error("逐管存档清单缺失")
    actual=Set(
        replace(relpath(joinpath(p, f), directory), '\\'=>'/') for (p, _, fs) in walkdir(directory)
        for f in fs
    )
    actual==union(required, Set(["files.toml"])) || error("逐管存档文件集合改变")
    for (p, h) in files
        !isabspath(p)&&!occursin(':', p)&&all(s->!(s in ("", ".", "..")), split(p, '/')) ||
            error("存档路径非法")
        bytes2hex(sha256(read(joinpath(directory, split(p, '/')...))))==h || error("逐管存档篡改")
    end
    c=load_r7_recovery_case(joinpath(directory, "case.toml"))
    s=TOML.parsefile(joinpath(directory, "spec.toml"))
    r=TOML.parsefile(joinpath(directory, "result.toml"))
    r["source_hashes_at_solve"]==r7_transport_science_hashes() || error("请用逐管记录原源码重验")
    all(files["code/"*p]==h for (p, h) in r["source_hashes_at_solve"]) || error("源码副本不符")
    validation=validate_r7_transport_recovery(c, s, r)
    isequal(validation, r["validation"]) || error("逐管原值与摘要不同")
    (; case = c, spec = s, result = r, validation)
end
