function r7_thermal_science_paths()
    root=normpath(joinpath(@__DIR__, "..", ".."))
    merge(
        r7_recovery_science_paths(),
        Dict("src/networks/r7_pipe_state.jl"=>joinpath(root, "src/networks/r7_pipe_state.jl")),
        Dict(
            "src/$layer/r7_thermal.jl"=>joinpath(root, "src", layer, "r7_thermal.jl") for
            layer in ("core", "formulations", "verification", "algorithms", "reporting")
        ),
    )
end
r7_thermal_science_hashes() =
    Dict(p=>bytes2hex(sha256(read(f))) for (p, f) in r7_thermal_science_paths())

"""保存新热重构原值、父恢复原值、显式空间状态、全部科学源码与哈希；拒绝覆盖和求解后源码漂移。"""
function save_r7_thermal_reconstruction(
    c::R7RecoveryCase,
    parent,
    spec,
    result,
    directory::AbstractString,
)
    result["source_hashes_at_solve"]==r7_thermal_science_hashes() || error("热重构求解后源码改变")
    isequal(validate_r7_thermal_reconstruction(c, parent, spec, result), result["validation"]) ||
        error("热重构汇总与数值不符")
    dest=abspath(directory)
    ispath(dest)&&error("不覆盖热重构证据")
    stage=dest*".writing-"*string(uuid4())
    mkpath(stage)
    for (file, obj) in (
        ("case.toml", c.data),
        ("parent.toml", parent),
        ("spec.toml", spec),
        ("result.toml", result),
    )
        write(joinpath(stage, file), r7_text(obj))
    end
    for (p, f) in r7_thermal_science_paths()
        target=joinpath(stage, "code", split(p, '/')...)
        mkpath(dirname(target))
        cp(f, target)
    end
    replay="module FrozenR7Thermal\nusing JuMP,TOML,SHA,Dates,UUIDs\nconst MOI=JuMP.MOI\n" *
           join(
               "include(\"src/$layer/r7_recovery.jl\")\n" for
               layer in ("core", "formulations", "verification", "algorithms", "reporting")
           ) *
           "include(\"src/networks/r7_pipe_state.jl\")\n" *
           join(
               "include(\"src/$layer/r7_thermal.jl\")\n" for
               layer in ("core", "formulations", "verification", "algorithms", "reporting")
           ) *
           "end\nx=FrozenR7Thermal.read_r7_thermal_reconstruction(joinpath(@__DIR__,\"..\"))\nprintln(x.result[\"status\"])\n"
    write(joinpath(stage, "code/replay.jl"), replay)
    hashes=Dict(
        replace(relpath(joinpath(p, f), stage), '\\'=>'/')=>bytes2hex(sha256(read(joinpath(p, f))))
        for (p, _, fs) in walkdir(stage) for f in fs
    )
    write(joinpath(stage, "files.toml"), r7_text(Dict("files"=>hashes)))
    mv(stage, dest)
    read_r7_thermal_reconstruction(dest)
    dest
end

"""只读重验热重构输入、父记录、源码和数值；源码升级后使用存档code/replay.jl，不重新优化。"""
function read_r7_thermal_reconstruction(directory::AbstractString)
    files=TOML.parsefile(joinpath(directory, "files.toml"))["files"]
    required=Set(
        vcat(
            ["case.toml", "parent.toml", "spec.toml", "result.toml", "code/replay.jl"],
            ["code/"*p for p in keys(r7_thermal_science_paths())],
        ),
    )
    Set(keys(files))==required || error("热重构清单不完整")
    actual=Set(
        replace(relpath(joinpath(p, f), directory), '\\'=>'/') for (p, _, fs) in walkdir(directory)
        for f in fs
    )
    actual==union(required, Set(["files.toml"])) || error("热重构存档文件集合不符")
    for (p, h) in files
        !isabspath(p)&&!occursin(':', p)&&all(s->!(s in ("", ".", "..")), split(p, '/')) ||
            error("存档路径非法")
        bytes2hex(sha256(read(joinpath(directory, split(p, '/')...))))==h || error("热重构文件篡改")
    end
    c=load_r7_recovery_case(joinpath(directory, "case.toml"))
    parent=TOML.parsefile(joinpath(directory, "parent.toml"))
    spec=TOML.parsefile(joinpath(directory, "spec.toml"))
    result=TOML.parsefile(joinpath(directory, "result.toml"))
    result["source_hashes_at_solve"]==r7_thermal_science_hashes() ||
        error("请用原热重构存档源码重验")
    all(files["code/"*p]==h for (p, h) in result["source_hashes_at_solve"]) || error("源码副本不符")
    validation=validate_r7_thermal_reconstruction(c, parent, spec, result)
    isequal(validation, result["validation"]) || error("热重构原值与汇总不同")
    (; case = c, parent, spec, result, validation)
end
