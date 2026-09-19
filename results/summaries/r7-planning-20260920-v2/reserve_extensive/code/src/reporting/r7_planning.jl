function r7_planning_science_paths()
    paths=r7_normal_science_paths()
    root=normpath(joinpath(@__DIR__, "..", ".."))
    for folder in ("core", "formulations", "verification", "algorithms", "reporting")
        p="src/$folder/r7_planning.jl"
        paths[p]=joinpath(root, split(p, '/')...)
    end
    paths
end
r7_planning_science_hashes() =
    Dict(p=>bytes2hex(sha256(read(file))) for (p, file) in r7_planning_science_paths())

function r7_planning_check_record(c, r)
    q=validate_r7_planning(c, r)
    isequal(q, r["validation"]) &&
    r["candidate_accepted"]==q["robust_model_pass"] &&
    r["conditional_cost_complete"]==q["conditional_optimality_pass"] ||
        error("规划原值与验收摘要不同")
    q
end

"""
    save_r7_planning(case, result, directory)

在新目录保存输入、事件规则、每轮正常/恢复原值、上下界与科学源码。拒绝覆盖和求解后源码漂移；
冻结replay.jl可只读回代，恢复见证与独立失供最优化记录分别保留。
"""
function save_r7_planning(c::R7PlanningCase, r, directory::AbstractString)
    r["source_hashes_at_solve"]==r7_planning_science_hashes() || error("规划求解后源码改变")
    r7_planning_check_record(c, r)
    dest=abspath(directory)
    ispath(dest)&&error("不覆盖旧规划运行")
    staging=dest*".writing-"*string(uuid4())
    mkpath(staging)
    for (p, data) in
        ("normal.toml"=>c.normal.data, "specification.toml"=>c.specification, "result.toml"=>r)
        write(joinpath(staging, p), r7_text(data))
    end
    root=normpath(joinpath(@__DIR__, "..", ".."))
    meta=Dict{String,Any}(
        "schema"=>"r7-planning-metadata-v1",
        "case_sha256"=>c.sha256,
        "run_id"=>r["run_id"],
        "origin"=>c.normal.data["origin"],
        "saved_utc"=>string(now(UTC)),
    )
    if ispath(joinpath(root, ".git"))
        meta["git_commit"]=readchomp(Cmd(["git", "-C", root, "rev-parse", "HEAD"]))
        meta["git_status"]=read(Cmd(["git", "-C", root, "status", "--short"]), String)
    end
    write(joinpath(staging, "metadata.toml"), r7_text(meta))
    for (p, file) in r7_planning_science_paths()
        target=joinpath(staging, "code", split(p, '/')...)
        mkpath(dirname(target))
        cp(file, target)
    end
    includes=[
        "core/r7_recovery.jl",
        "formulations/r7_recovery.jl",
        "verification/r7_recovery.jl",
        "algorithms/r7_recovery.jl",
        "reporting/r7_recovery.jl",
        "core/r7_commitment.jl",
        "components/r7_commitment.jl",
        "verification/r7_commitment.jl",
        "networks/r7_pipe_state.jl",
        "networks/fixed_flow_heat.jl",
        "core/r7_normal.jl",
        "networks/r7_normal_transport.jl",
        "formulations/r7_normal.jl",
        "verification/r7_normal.jl",
        "algorithms/r7_normal.jl",
        "reporting/r7_normal.jl",
        "core/r7_planning.jl",
        "formulations/r7_planning.jl",
        "verification/r7_planning.jl",
        "algorithms/r7_planning.jl",
        "reporting/r7_planning.jl",
    ]
    replay="module FrozenR7Planning\nusing JuMP,TOML,SHA,Dates,UUIDs\nconst MOI=JuMP.MOI\n" *
           join("include(\"src/$p\")\n" for p in includes) *
           "end\nx=FrozenR7Planning.read_r7_planning(joinpath(@__DIR__,\"..\"))\nprintln(x.result[\"status\"],\" robust=\",x.validation[\"robust_model_pass\"])\n"
    write(joinpath(staging, "code/replay.jl"), replay)
    hashes=Dict(
        replace(relpath(joinpath(p, f), staging), '\\'=>'/')=>bytes2hex(
            sha256(read(joinpath(p, f))),
        ) for (p, _, fs) in walkdir(staging) for f in fs
    )
    write(joinpath(staging, "files.toml"), r7_text(Dict("files"=>hashes)))
    mv(staging, dest)
    read_r7_planning(dest)
    dest
end

"""只读核验有限故障规划的完整文件清单、输入、原值、事件证书和科学源码，不重新优化。"""
function read_r7_planning(directory::AbstractString)
    hashes=TOML.parsefile(joinpath(directory, "files.toml"))["files"]
    required=Set(
        vcat(
            ["normal.toml", "specification.toml", "result.toml", "metadata.toml", "code/replay.jl"],
            ["code/"*p for p in keys(r7_planning_science_paths())],
        ),
    )
    Set(keys(hashes))==required || error("规划存档清单缺项")
    actual=Set(
        replace(relpath(joinpath(p, f), directory), '\\'=>'/') for (p, _, fs) in walkdir(directory)
        for f in fs
    )
    actual==union(required, Set(["files.toml"])) || error("规划存档文件集合不符")
    for (p, hash) in hashes
        !isabspath(p)&&!occursin(':', p)&&!occursin('\\', p)&&all(
            x->!(x in ("", ".", "..")),
            split(p, '/'),
        ) || error("规划存档路径非法")
        bytes2hex(sha256(read(joinpath(directory, split(p, '/')...))))==hash ||
            error("规划存档被改变")
    end
    c=load_r7_planning_case(
        joinpath(directory, "normal.toml"),
        joinpath(directory, "specification.toml"),
    )
    r=TOML.parsefile(joinpath(directory, "result.toml"))
    meta=TOML.parsefile(joinpath(directory, "metadata.toml"))
    meta["schema"]=="r7-planning-metadata-v1"&&meta["case_sha256"]==c.sha256&&meta["run_id"]==r["run_id"]&&meta["origin"]==c.normal.data["origin"] ||
        error("规划存档身份错误")
    r["source_hashes_at_solve"]==r7_planning_science_hashes() ||
        error("请用冻结code/replay.jl重验规划结果")
    all(get(hashes, "code/"*p, "")==h for (p, h) in r["source_hashes_at_solve"]) ||
        error("规划科学源码副本错误")
    q=r7_planning_check_record(c, r)
    (; case = c, result = r, validation = q)
end
