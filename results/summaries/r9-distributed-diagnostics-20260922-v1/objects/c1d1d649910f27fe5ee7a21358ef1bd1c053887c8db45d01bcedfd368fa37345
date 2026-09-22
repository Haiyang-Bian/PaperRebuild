function r9_detailed_preplan_science_paths()
    paths = merge(r7_linked_science_paths(), r9_preplan_science_paths())
    root = normpath(joinpath(@__DIR__, "..", ".."))
    for layer in ("core", "formulations", "verification", "algorithms", "reporting")
        p = "src/$layer/r9_detailed_preplan.jl"
        paths[p] = joinpath(root, p)
    end
    paths["src/verification/r9_handoff.jl"] = joinpath(root, "src/verification/r9_handoff.jl")
    paths
end
r9_detailed_preplan_science_hashes() =
    Dict(p => bytes2hex(sha256(read(f))) for (p, f) in r9_detailed_preplan_science_paths())

function r9_detailed_preplan_includes()
    paths = String[]
    for name in ("recovery", "adversary"),
        layer in ("core", "formulations", "verification", "algorithms", "reporting")

        push!(paths, "src/$layer/r7_$name.jl")
    end
    append!(
        paths,
        "src/" .* [
            "core/r7_commitment.jl",
            "components/r7_commitment.jl",
            "verification/r7_commitment.jl",
            "networks/r7_pipe_state.jl",
            "networks/fixed_flow_heat.jl",
            "core/r7_initial_profile.jl",
        ],
    )
    for name in ("thermal", "transport", "normal", "planning", "linked_planning")
        push!(paths, "src/core/r7_$name.jl")
        name == "normal" && push!(paths, "src/networks/r7_normal_transport.jl")
        name == "linked_planning" && push!(paths, "src/networks/r7_linked_state.jl")
        for layer in ("formulations", "verification", "algorithms", "reporting")
            push!(paths, "src/$layer/r7_$name.jl")
        end
    end
    push!(paths, "src/core/r8_tradeoff.jl")
    for name in ("preplan", "detailed_preplan"),
        layer in ("core", "formulations", "verification", "algorithms", "reporting")

        push!(paths, "src/$layer/r9_$name.jl")
    end
    push!(paths, "src/verification/r9_handoff.jl")
    Set(paths) == setdiff(
        Set(keys(r9_detailed_preplan_science_paths())),
        Set(["Project.toml", "Manifest.toml", "src/PaperRebuild.jl"]),
    ) || error("详细灾前冻结依赖集合失步")
    paths
end

function r9_detailed_preplan_check_record(c, s, r)
    q = validate_r9_detailed_preplan(c, s, r)
    isequal(q, r["validation"]) &&
    r["candidate_accepted"] == q["model_pass"] &&
    r["conditional_objective_complete"] == q["objective_optimality_pass"] ||
        error("详细灾前摘要与原值失步")
    q
end

"""R9-DP3：保存详细灾前输入、原值、来源和可移位验证源码；拒绝覆盖及求解后源码变化。"""
function save_r9_detailed_preplan(c::R7PlanningCase, s, r, directory::AbstractString)
    r["source_hashes_at_solve"] == r9_detailed_preplan_science_hashes() || error("求解后源码改变")
    r9_detailed_preplan_check_record(c, s, r)
    includes = r9_detailed_preplan_includes()
    dest = abspath(directory)
    ispath(dest) && error("不覆盖详细灾前运行")
    stage = dest * ".writing-" * string(uuid4())
    mkpath(stage)
    for (p, value) in (
        "normal.toml" => c.normal.data,
        "planning.toml" => c.specification,
        "spec.toml" => s,
        "result.toml" => r,
    )
        write(joinpath(stage, p), r7_text(value))
    end
    meta = Dict{String,Any}(
        "schema" => "r9-detailed-preplan-metadata-v1",
        "run_id" => r["run_id"],
        "case_sha256" => c.sha256,
        "spec_sha256" => r7_digest(s),
        "origin" => c.normal.data["origin"],
        "saved_utc" => string(now(UTC)),
    )
    root = normpath(joinpath(@__DIR__, "..", ".."))
    if ispath(joinpath(root, ".git"))
        meta["git_commit"] = readchomp(Cmd(["git", "-C", root, "rev-parse", "HEAD"]))
        meta["git_status"] = read(Cmd(["git", "-C", root, "status", "--short"]), String)
    end
    write(joinpath(stage, "metadata.toml"), r7_text(meta))
    for (p, file) in r9_detailed_preplan_science_paths()
        target = joinpath(stage, "code", p)
        mkpath(dirname(target))
        cp(file, target)
    end
    replay =
        "module FrozenR9Detailed\nusing JuMP,TOML,SHA,Dates,UUIDs\nconst MOI=JuMP.MOI\n" *
        join("include(\"$p\")\n" for p in includes) *
        "end\nx=FrozenR9Detailed.read_r9_detailed_preplan(joinpath(@__DIR__,\"..\"))\nprintln(x.result[\"status\"],\" detailed=\",x.validation[\"model_pass\"])\n"
    write(joinpath(stage, "code/replay.jl"), replay)
    files = Dict(
        replace(relpath(joinpath(p, f), stage), '\\' => '/') =>
            bytes2hex(sha256(read(joinpath(p, f)))) for (p, _, fs) in walkdir(stage) for f in fs
    )
    write(joinpath(stage, "files.toml"), r7_text(Dict("files" => files)))
    mv(stage, dest)
    read_r9_detailed_preplan(dest)
    dest
end

"""R9-DP3：从完整清单与冻结数值重验详细灾前见证；冻结code/replay.jl不重新调用求解器。"""
function read_r9_detailed_preplan(directory::AbstractString)
    hashes = TOML.parsefile(joinpath(directory, "files.toml"))["files"]
    required = Set(
        vcat(
            [
                "normal.toml",
                "planning.toml",
                "spec.toml",
                "result.toml",
                "metadata.toml",
                "code/replay.jl",
            ],
            ["code/" * p for p in keys(r9_detailed_preplan_science_paths())],
        ),
    )
    Set(keys(hashes)) == required || error("详细灾前存档清单缺项")
    actual = Set(
        replace(relpath(joinpath(p, f), directory), '\\' => '/') for
        (p, _, fs) in walkdir(directory) for f in fs
    )
    actual == union(required, Set(["files.toml"])) || error("详细灾前存档文件集合错误")
    for (p, h) in hashes
        !isabspath(p) &&
        !occursin(':', p) &&
        !occursin('\\', p) &&
        all(x -> !(x in ("", ".", "..")), split(p, '/')) || error("存档路径非法")
        bytes2hex(sha256(read(joinpath(directory, p)))) == h || error("存档字节被修改")
    end
    c = load_r7_planning_case(
        joinpath(directory, "normal.toml"),
        joinpath(directory, "planning.toml"),
    )
    s = TOML.parsefile(joinpath(directory, "spec.toml"))
    r = TOML.parsefile(joinpath(directory, "result.toml"))
    meta = TOML.parsefile(joinpath(directory, "metadata.toml"))
    meta["schema"] == "r9-detailed-preplan-metadata-v1" &&
    meta["case_sha256"] == c.sha256 &&
    meta["spec_sha256"] == r7_digest(s) &&
    meta["run_id"] == r["run_id"] &&
    meta["origin"] == c.normal.data["origin"] || error("存档来源不同")
    r["source_hashes_at_solve"] == r9_detailed_preplan_science_hashes() ||
        error("请用冻结code/replay.jl重验")
    all(get(hashes, "code/" * p, "") == h for (p, h) in r["source_hashes_at_solve"]) ||
        error("源码副本不同")
    q = r9_detailed_preplan_check_record(c, s, r)
    (; case = c, spec = s, result = r, validation = q)
end
