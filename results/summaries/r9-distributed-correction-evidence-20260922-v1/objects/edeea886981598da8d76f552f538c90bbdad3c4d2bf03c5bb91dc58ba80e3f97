function r9_preplan_science_paths()
    paths=r7_planning_science_paths()
    root=normpath(joinpath(@__DIR__, "..", ".."))
    paths["src/core/r8_tradeoff.jl"]=joinpath(root, "src/core/r8_tradeoff.jl")
    for dir in ("core", "formulations", "verification", "algorithms", "reporting")
        p="src/$dir/r9_preplan.jl"
        paths[p]=joinpath(root, p)
    end
    paths
end
r9_preplan_science_hashes() =
    Dict(p=>bytes2hex(sha256(read(f))) for (p, f) in r9_preplan_science_paths())

function r9_preplan_check_record(c, s, r)
    q=validate_r9_preplan(c, s, r)
    isequal(q, r["validation"]) &&
    r["candidate_accepted"]==q["model_pass"] &&
    r["conditional_objective_complete"]==q["objective_optimality_pass"] ||
        error("灾前摘要与原值失步")
    q
end

"""保存灾前对照输入、子集、载体、原值和科学源码到新目录；拒绝覆盖或求解后源码变化。"""
function save_r9_preplan(c::R7PlanningCase, s, r, directory::AbstractString)
    r["source_hashes_at_solve"]==r9_preplan_science_hashes() || error("灾前求解后源码改变")
    r9_preplan_check_record(c, s, r)
    dest=abspath(directory)
    ispath(dest) && error("不覆盖已有灾前对照运行")
    stage=dest*".writing-"*string(uuid4())
    mkpath(stage)
    for (p, v) in (
        "normal.toml"=>c.normal.data,
        "planning.toml"=>c.specification,
        "spec.toml"=>s,
        "carrier.toml"=>r9_preplan_carrier(c, s).specification,
        "result.toml"=>r,
    )
        write(joinpath(stage, p), r7_text(v))
    end
    meta=Dict{String,Any}(
        "schema"=>"r9-preplan-metadata-v1",
        "run_id"=>r["run_id"],
        "case_sha256"=>c.sha256,
        "spec_sha256"=>r7_digest(s),
        "origin"=>c.normal.data["origin"],
        "saved_utc"=>string(now(UTC)),
    )
    root=normpath(joinpath(@__DIR__, "..", ".."))
    if ispath(joinpath(root, ".git"))
        meta["git_commit"]=readchomp(Cmd(["git", "-C", root, "rev-parse", "HEAD"]))
        meta["git_status"]=read(Cmd(["git", "-C", root, "status", "--short"]), String)
    end
    write(joinpath(stage, "metadata.toml"), r7_text(meta))
    for (p, file) in r9_preplan_science_paths()
        target=joinpath(stage, "code", p)
        mkpath(dirname(target))
        cp(file, target)
    end
    includes=[
        "core/r7_recovery.jl",
        "formulations/r7_recovery.jl",
        "verification/r7_recovery.jl",
        "algorithms/r7_recovery.jl",
        "reporting/r7_recovery.jl",
        "core/r7_adversary.jl",
        "formulations/r7_adversary.jl",
        "verification/r7_adversary.jl",
        "algorithms/r7_adversary.jl",
        "reporting/r7_adversary.jl",
        "core/r7_commitment.jl",
        "components/r7_commitment.jl",
        "verification/r7_commitment.jl",
        "networks/r7_pipe_state.jl",
        "networks/fixed_flow_heat.jl",
        "core/r7_initial_profile.jl",
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
        "core/r8_tradeoff.jl",
        "core/r9_preplan.jl",
        "formulations/r9_preplan.jl",
        "verification/r9_preplan.jl",
        "algorithms/r9_preplan.jl",
        "reporting/r9_preplan.jl",
    ]
    replay="module FrozenR9Preplan\nusing JuMP,TOML,SHA,Dates,UUIDs\nconst MOI=JuMP.MOI\n" *
           join("include(\"src/$p\")\n" for p in includes) *
           "end\nx=FrozenR9Preplan.read_r9_preplan(joinpath(@__DIR__,\"..\"))\nprintln(x.result[\"status\"],\" adopted=\",x.validation[\"model_pass\"])\n"
    write(joinpath(stage, "code/replay.jl"), replay)
    hashes=Dict(
        replace(relpath(joinpath(p, f), stage), '\\'=>'/')=>bytes2hex(sha256(read(joinpath(p, f))))
        for (p, _, fs) in walkdir(stage) for f in fs
    )
    write(joinpath(stage, "files.toml"), r7_text(Dict("files"=>hashes)))
    mv(stage, dest)
    read_r9_preplan(dest)
    dest
end

"""从完整哈希清单和原保存值重验灾前对照；可由随附code/replay.jl移位执行，不重新优化。"""
function read_r9_preplan(directory::AbstractString)
    hashes=TOML.parsefile(joinpath(directory, "files.toml"))["files"]
    required=Set(
        vcat(
            [
                "normal.toml",
                "planning.toml",
                "spec.toml",
                "carrier.toml",
                "result.toml",
                "metadata.toml",
                "code/replay.jl",
            ],
            ["code/"*p for p in keys(r9_preplan_science_paths())],
        ),
    )
    Set(keys(hashes))==required || error("灾前存档清单缺项")
    actual=Set(
        replace(relpath(joinpath(p, f), directory), '\\'=>'/') for (p, _, fs) in walkdir(directory)
        for f in fs
    )
    actual==union(required, Set(["files.toml"])) || error("灾前存档文件集合错误")
    for (p, h) in hashes
        !isabspath(p) &&
        !occursin(':', p) &&
        !occursin('\\', p) &&
        all(x->!(x in ("", ".", "..")), split(p, '/')) || error("灾前存档路径非法")
        bytes2hex(sha256(read(joinpath(directory, p))))==h || error("灾前存档字节被修改")
    end
    c=load_r7_planning_case(
        joinpath(directory, "normal.toml"),
        joinpath(directory, "planning.toml"),
    )
    s=TOML.parsefile(joinpath(directory, "spec.toml"))
    r=TOML.parsefile(joinpath(directory, "result.toml"))
    meta=TOML.parsefile(joinpath(directory, "metadata.toml"))
    meta["schema"]=="r9-preplan-metadata-v1" &&
    meta["case_sha256"]==c.sha256 &&
    meta["spec_sha256"]==r7_digest(s) &&
    meta["run_id"]==r["run_id"] &&
    meta["origin"]==c.normal.data["origin"] || error("灾前存档来源不同")
    isequal(
        TOML.parsefile(joinpath(directory, "carrier.toml")),
        r9_preplan_carrier(c, s).specification,
    ) || error("载体改变了声明之外的规则")
    r["source_hashes_at_solve"]==r9_preplan_science_hashes() || error("请用冻结code/replay.jl重验")
    all(get(hashes, "code/"*p, "")==h for (p, h) in r["source_hashes_at_solve"]) ||
        error("源码副本不同")
    q=r9_preplan_check_record(c, s, r)
    (; case = c, spec = s, result = r, validation = q)
end
