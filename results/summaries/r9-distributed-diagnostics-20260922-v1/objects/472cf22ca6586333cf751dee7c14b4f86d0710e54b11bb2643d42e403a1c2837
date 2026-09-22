function r7_flow_planning_includes()
    paths=String[]
    for name in ("recovery", "adversary")
        append!(
            paths,
            [
                "src/$layer/r7_$name.jl" for
                layer in ("core", "formulations", "verification", "algorithms", "reporting")
            ],
        )
    end
    append!(
        paths,
        [
            "src/core/r7_commitment.jl",
            "src/components/r7_commitment.jl",
            "src/verification/r7_commitment.jl",
            "src/networks/r7_pipe_state.jl",
            "src/networks/fixed_flow_heat.jl",
            "src/core/r7_initial_profile.jl",
        ],
    )
    for name in (
        "thermal",
        "transport",
        "normal",
        "planning",
        "linked_planning",
        "normal_flow",
        "flow_planning",
    )
        push!(paths, "src/core/r7_$name.jl")
        name=="normal"&&push!(paths, "src/networks/r7_normal_transport.jl")
        name=="linked_planning"&&push!(paths, "src/networks/r7_linked_state.jl")
        name=="normal_flow"&&push!(paths, "src/networks/r7_mass_overlap.jl")
        name=="normal_flow"&&push!(paths, "src/networks/r7_lossy_mass.jl")
        append!(
            paths,
            [
                "src/$layer/r7_$name.jl" for
                layer in ("formulations", "verification", "algorithms", "reporting")
            ],
        )
    end
    paths
end

function r7_flow_planning_science_paths()
    root=normpath(joinpath(@__DIR__, "..", ".."))
    Dict(
        p=>joinpath(root, split(p, '/')...) for p in
        vcat(r7_flow_planning_includes(), ["src/PaperRebuild.jl", "Project.toml", "Manifest.toml"])
    )
end
r7_flow_planning_science_hashes() =
    Dict(p=>bytes2hex(sha256(read(f))) for (p, f) in r7_flow_planning_science_paths())

function r7_flow_planning_record_check(c, s, r)
    q=validate_r7_flow_planning(c, s, r)
    isequal(q, r["validation"])&&r["candidate_accepted"]==q["robust_model_pass"] &&
    r["domain_cost_complete"]==q["domain_optimality_pass"] || error("联合流量原值与摘要不同")
    q
end

"""
    save_r7_flow_planning(case, spec, result, directory)

冻结共同正常输入、流量域、全部故障原值、继承边界及科学源码。拒绝覆盖已有目录或保存源码已变的求解。
文件清单同时核验完整性与哈希；原运行状态/负结果保留，不以新一轮优化冒充重读。
"""
function save_r7_flow_planning(c, s, r, directory::AbstractString)
    r["source_hashes_at_solve"]==r7_flow_planning_science_hashes() ||
        error("联合流量求解后源码变化")
    r7_flow_planning_record_check(c, s, r)
    dest=abspath(directory)
    ispath(dest)&&error("不覆盖联合流量记录")
    stage=dest*".writing-"*string(uuid4())
    mkpath(stage)
    for (p, x) in (
        "normal.toml"=>c.normal.data,
        "planning.toml"=>c.specification,
        "spec.toml"=>s,
        "result.toml"=>r,
    )
        write(joinpath(stage, p), r7_text(x))
    end
    for (p, f) in r7_flow_planning_science_paths()
        target=joinpath(stage, "code", split(p, '/')...)
        mkpath(dirname(target))
        cp(f, target)
    end
    replay="module FrozenR7FlowPlanning\nusing JuMP,TOML,SHA,Dates,UUIDs\nconst MOI=JuMP.MOI\n" *
           join("include(\"$p\")\n" for p in r7_flow_planning_includes()) *
           "end\nx=FrozenR7FlowPlanning.read_r7_flow_planning(joinpath(@__DIR__,\"..\"))\nprintln(x.result[\"status\"],\" robust=\",x.validation[\"robust_model_pass\"])\n"
    write(joinpath(stage, "code/replay.jl"), replay)
    files=Dict(
        replace(relpath(joinpath(p, f), stage), '\\'=>'/')=>bytes2hex(sha256(read(joinpath(p, f))))
        for (p, _, fs) in walkdir(stage) for f in fs
    )
    write(joinpath(stage, "files.toml"), r7_text(Dict("files"=>files)))
    mv(stage, dest)
    read_r7_flow_planning(dest)
    dest
end

"""核对联合流量文件集合、输入/源码哈希并按保存值重放；源码变更后使用记录内code/replay.jl。"""
function read_r7_flow_planning(directory::AbstractString)
    hashes=TOML.parsefile(joinpath(directory, "files.toml"))["files"]
    required=Set(
        vcat(
            ["normal.toml", "planning.toml", "spec.toml", "result.toml", "code/replay.jl"],
            "code/" .* collect(keys(r7_flow_planning_science_paths())),
        ),
    )
    Set(keys(hashes))==required || error("联合流量文件清单缺项")
    actual=Set(
        replace(relpath(joinpath(p, f), directory), '\\'=>'/') for (p, _, fs) in walkdir(directory)
        for f in fs
    )
    actual==union(required, Set(["files.toml"])) || error("联合流量存档文件集合改变")
    for (p, h) in hashes
        !isabspath(p)&&!occursin(':', p)&&!occursin('\\', p)&&all(
            x->!(x in ("", ".", "..")),
            split(p, '/'),
        ) || error("联合流量存档路径非法")
        bytes2hex(sha256(read(joinpath(directory, split(p, '/')...))))==h ||
            error("联合流量存档篡改")
    end
    c=load_r7_planning_case(
        joinpath(directory, "normal.toml"),
        joinpath(directory, "planning.toml"),
    )
    s=TOML.parsefile(joinpath(directory, "spec.toml"))
    r=TOML.parsefile(joinpath(directory, "result.toml"))
    r["source_hashes_at_solve"]==r7_flow_planning_science_hashes() ||
        error("请使用冻结code/replay.jl重验")
    all(hashes["code/"*p]==h for (p, h) in r["source_hashes_at_solve"]) ||
        error("联合流量源码副本身份错误")
    (; case = c, spec = s, result = r, validation = r7_flow_planning_record_check(c, s, r))
end
