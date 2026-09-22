function r7_normal_flow_includes()
    x=[
        "$layer/r7_recovery.jl" for
        layer in ("core", "formulations", "verification", "algorithms", "reporting")
    ]
    append!(
        x,
        [
            "core/r7_commitment.jl",
            "components/r7_commitment.jl",
            "verification/r7_commitment.jl",
            "networks/r7_pipe_state.jl",
            "networks/fixed_flow_heat.jl",
            "core/r7_initial_profile.jl",
            "core/r7_normal.jl",
            "networks/r7_normal_transport.jl",
        ],
    )
    append!(
        x,
        [
            "$layer/r7_normal.jl" for
            layer in ("formulations", "verification", "algorithms", "reporting")
        ],
    )
    append!(
        x,
        ["core/r7_normal_flow.jl", "networks/r7_mass_overlap.jl", "networks/r7_lossy_mass.jl"],
    )
    append!(
        x,
        [
            "$layer/r7_normal_flow.jl" for
            layer in ("formulations", "verification", "algorithms", "reporting")
        ],
    )
    "src/" .* x
end
function r7_normal_flow_science_paths()
    root=normpath(joinpath(@__DIR__, "..", ".."))
    Dict(
        p=>joinpath(root, split(p, '/')...) for p in
        vcat(r7_normal_flow_includes(), ["src/PaperRebuild.jl", "Project.toml", "Manifest.toml"])
    )
end
r7_normal_flow_science_hashes() =
    Dict(p=>bytes2hex(sha256(read(f))) for (p, f) in r7_normal_flow_science_paths())

function r7_normal_flow_record_check(c, s, r)
    q=validate_r7_normal_flow(c, s, r)
    isequal(q, r["validation"])&&r["candidate_accepted"]==q["model_pass"]&&r["domain_cost_complete"]==q["optimality_pass"] ||
        error("连续流量原值与摘要不同")
    q
end

"""冻结连续流量正常运行、边界、原值及科学源码；禁止覆盖旧目录，求解后源码变化拒绝保存。"""
function save_r7_normal_flow(c, s, r, directory::AbstractString)
    r["source_hashes_at_solve"]==r7_normal_flow_science_hashes() || error("连续流量求解后源码变化")
    r7_normal_flow_record_check(c, s, r)
    dest=abspath(directory)
    ispath(dest)&&error("不覆盖连续流量记录")
    stage=dest*".writing-"*string(uuid4())
    mkpath(stage)
    for (p, x) in ("case.toml"=>c.data, "spec.toml"=>s, "result.toml"=>r)
        write(joinpath(stage, p), r7_text(x))
    end
    for (p, f) in r7_normal_flow_science_paths()
        target=joinpath(stage, "code", split(p, '/')...)
        mkpath(dirname(target))
        cp(f, target)
    end
    replay="module FrozenR7NormalFlow\nusing JuMP,TOML,SHA,Dates,UUIDs\nconst MOI=JuMP.MOI\n" *
           join("include(\"$p\")\n" for p in r7_normal_flow_includes()) *
           "end\nx=FrozenR7NormalFlow.read_r7_normal_flow(joinpath(@__DIR__,\"..\"))\nprintln(x.result[\"status\"],\" flow=\",x.validation[\"model_pass\"])\n"
    write(joinpath(stage, "code/replay.jl"), replay)
    files=Dict(
        replace(relpath(joinpath(p, f), stage), '\\'=>'/')=>bytes2hex(sha256(read(joinpath(p, f))))
        for (p, _, fs) in walkdir(stage) for f in fs
    )
    write(joinpath(stage, "files.toml"), r7_text(Dict("files"=>files)))
    mv(stage, dest)
    read_r7_normal_flow(dest)
    dest
end

"""按冻结源码与哈希只读重验连续流量运行，独立回放所有原值；不重新优化。"""
function read_r7_normal_flow(directory::AbstractString)
    hashes=TOML.parsefile(joinpath(directory, "files.toml"))["files"]
    required=Set(
        vcat(
            ["case.toml", "spec.toml", "result.toml", "code/replay.jl"],
            "code/" .* collect(keys(r7_normal_flow_science_paths())),
        ),
    )
    Set(keys(hashes))==required || error("连续流量文件清单缺项")
    actual=Set(
        replace(relpath(joinpath(p, f), directory), '\\'=>'/') for (p, _, fs) in walkdir(directory)
        for f in fs
    )
    actual==union(required, Set(["files.toml"])) || error("连续流量存档文件集合改变")
    for (p, h) in hashes
        !isabspath(p)&&!occursin(':', p)&&!occursin('\\', p)&&all(
            x->!(x in ("", ".", "..")),
            split(p, '/'),
        ) || error("连续流量存档路径非法")
        bytes2hex(sha256(read(joinpath(directory, split(p, '/')...))))==h ||
            error("连续流量存档篡改")
    end
    c=load_r7_normal_case(joinpath(directory, "case.toml"))
    s=TOML.parsefile(joinpath(directory, "spec.toml"))
    r=TOML.parsefile(joinpath(directory, "result.toml"))
    r["source_hashes_at_solve"]==r7_normal_flow_science_hashes() ||
        error("请使用冻结code/replay.jl重验")
    all(hashes["code/"*p]==h for (p, h) in r["source_hashes_at_solve"]) ||
        error("连续流量源码副本身份不符")
    (; case = c, spec = s, result = r, validation = r7_normal_flow_record_check(c, s, r))
end
