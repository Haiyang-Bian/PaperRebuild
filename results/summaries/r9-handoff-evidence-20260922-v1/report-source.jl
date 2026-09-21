module R9HandoffEvidence
using PaperRebuild, TOML, SHA, Dates
include("r9_resilience_evidence.jl")
const Archive = R9ResilienceEvidence
const Objects = Archive.Objects
const PR = PaperRebuild
const ROOT = dirname(@__DIR__)
hashfile(p) = bytes2hex(sha256(read(p)))
files(folder) = Dict(
    replace(relpath(joinpath(d, f), folder), '\\' => '/') => hashfile(joinpath(d, f)) for
    (d, _, fs) in walkdir(folder) for f in fs
)

function frozen_parent(dir)
    m = Module(gensym(:HandoffParent))
    Base.include(m, joinpath(dir, "code/replay.jl"))
    Base.invokelatest(getfield, m, :x)
end

function evaluate(folder)
    scratch = isdir(joinpath(ROOT, "tmp")) ? joinpath(ROOT, "tmp") : tempdir()
    parents = mktempdir(scratch; prefix = "r9-handoff-parents-", cleanup = false)
    index = TOML.parsefile(joinpath(folder, "parents.toml"))
    for label in ("baseline", "candidate")
        Archive.extract(folder, index[label], joinpath(parents, label))
    end
    m = Module(gensym(:HandoffKernel))
    Base.include(m, joinpath(folder, "kernel/replay.jl"))
    K = Base.invokelatest(getfield, m, :FrozenHandoff)
    loadcase = Base.invokelatest(getfield, K, :load_r7_recovery_case)
    checker = Base.invokelatest(getfield, K, :r9_handoff_temperature_check)
    result = Dict{String,Any}()
    for label in ("baseline", "candidate")
        dir = joinpath(parents, label)
        old = frozen_parent(dir)
        c = Base.invokelatest(loadcase, joinpath(dir, "case.toml"))
        s = TOML.parsefile(joinpath(dir, "spec.toml"))
        q = Base.invokelatest(checker, c, s)
        result[label] = Dict(
            "parent_manifest_sha256" => hashfile(joinpath(dir, "files.toml")),
            "parent_status" => old.result["status"],
            "original_model_pass" => old.validation["model_pass"],
            "necessary_check" => q,
        )
    end
    protocol = TOML.parsefile(joinpath(folder, "iis-protocol.toml"))
    diagnostic = TOML.parsefile(joinpath(folder, "iis-diagnostic.toml"))
    protocol["parent_manifest_sha256"] == result["candidate"]["parent_manifest_sha256"] ||
        error("IIS并非同一继承候选")
    diagnostic["status"] == "INFEASIBLE" &&
    diagnostic["conflict_status"] == "CONFLICT_FOUND" &&
    diagnostic["parent_unchanged"] &&
    diagnostic["source_unchanged"] || error("IIS状态证据缺失")
    equality =
        only(filter(r -> startswith(r["set"], "MathOptInterface.EqualTo"), diagnostic["rows"]))
    lower =
        only(filter(r -> startswith(r["set"], "MathOptInterface.GreaterThan"), diagnostic["rows"]))
    variable = only(equality["terms"])["variable"]
    only(lower["terms"])["variable"] == variable &&
    only(lower["terms"])["coefficient"] == 1 &&
    only(equality["terms"])["coefficient"] == 1 || error("冲突行对象或符号不同")
    ids = match(r"out_S\[(\d+),(\d+),(\d+)\]", variable)
    ids === nothing && error("未支持的冲突变量")
    a, k, w = parse.(Int, ids.captures)
    fixed =
        parse(Float64, only(match(r"EqualTo\{Float64\}\(([-0-9.e+]+)\)", equality["set"]).captures))
    bound = parse(
        Float64,
        only(match(r"GreaterThan\{Float64\}\(([-0-9.e+]+)\)", lower["set"]).captures),
    )
    q = result["candidate"]["necessary_check"]
    row = only(
        filter(
            r ->
                r["pipe"] == a &&
                r["side"] == "S" &&
                r["substep"] == k &&
                r["scenario"] == w &&
                haskey(r, "inlet_independent"),
            q["rows"],
        ),
    )
    row["inlet_independent"] &&
    row["conflict"] &&
    fixed < bound &&
    abs(row["upper_response_K"] - fixed) <= 1e-10 &&
    row["minimum_K"] == bound || error("独立回放不能支持保存IIS的温度矛盾")
    result["conflict_proof"] = Dict(
        "pipe" => a,
        "substep" => k,
        "scenario" => w,
        "fixed_outlet_K" => fixed,
        "lower_bound_K" => bound,
        "gap_K" => bound - fixed,
        "inlet_independent" => true,
        "original_solver_not_rerun" => true,
    )
    result
end

function freeze(baseline, candidate, iis, out)
    ispath(out) && error("不覆盖温区证据")
    for dir in (baseline, candidate)
        frozen_parent(dir)
    end
    ih = TOML.parsefile(joinpath(iis, "files.toml"))["files"]
    actual = files(iis)
    delete!(actual, "files.toml")
    ih == actual || error("IIS原存档字节改变")
    stage = out * ".writing"
    ispath(stage) && error("温区封存暂存目录已存在")
    mkpath(joinpath(stage, "objects"))
    index = Dict(
        "baseline" => Objects.pack(stage, baseline),
        "candidate" => Objects.pack(stage, candidate),
    )
    write(joinpath(stage, "parents.toml"), PR.r7_text(index))
    for name in ("protocol.toml", "diagnostic.toml", "files.toml")
        cp(joinpath(iis, name), joinpath(stage, "iis-" * name))
    end
    paths = merge(
        PR.r7_transport_science_paths(),
        Dict("src/verification/r9_handoff.jl" =>
                joinpath(ROOT, "src/verification/r9_handoff.jl")),
    )
    for (name, path) in paths
        dest = joinpath(stage, "kernel", name)
        mkpath(dirname(dest))
        cp(path, dest)
    end
    layers = ("core", "formulations", "verification", "algorithms", "reporting")
    includes = ["src/$layer/r7_recovery.jl" for layer in layers]
    push!(includes, "src/networks/r7_pipe_state.jl")
    for name in ("thermal", "transport"), layer in layers
        push!(includes, "src/$layer/r7_$name.jl")
    end
    push!(includes, "src/verification/r9_handoff.jl")
    Set(includes) ==
    setdiff(Set(keys(paths)), Set(["Project.toml", "Manifest.toml", "src/PaperRebuild.jl"])) ||
        error("温区回放依赖不闭合")
    write(
        joinpath(stage, "kernel/replay.jl"),
        "module FrozenHandoff\nusing JuMP,TOML,SHA,Dates,UUIDs\nconst MOI=JuMP.MOI\n" *
        join("include(\"$p\")\n" for p in includes) *
        "end\n",
    )
    result = evaluate(stage)
    result_hash = Objects.object(stage, Vector{UInt8}(codeunits(PR.r7_text(result))))
    write(joinpath(stage, "result-index.toml"), PR.r7_text(Dict("result_sha256" => result_hash)))
    summary = Dict(
        label => Dict(
            "parent_status" => result[label]["parent_status"],
            "necessary_condition_pass" =>
                result[label]["necessary_check"]["necessary_condition_pass"],
            "conflict_count" => result[label]["necessary_check"]["conflict_count"],
            "maximum_unavoidable_violation_K" =>
                result[label]["necessary_check"]["maximum_unavoidable_violation_K"],
        ) for label in ("baseline", "candidate")
    )
    summary["conflict_proof"] = result["conflict_proof"]
    write(joinpath(stage, "summary.toml"), PR.r7_text(summary))
    cp(@__FILE__, joinpath(stage, "report-source.jl"))
    for name in ("r9_resilience_evidence.jl", "r9_fixed_evidence.jl")
        cp(joinpath(@__DIR__, name), joinpath(stage, name))
    end
    write(
        joinpath(stage, "scope.toml"),
        PR.r7_text(
            Dict(
                "schema" => "r9-handoff-evidence-v1",
                "utc" => string(now(UTC)),
                "origin" => "frozen replacement-scale normal states and prescribed recovery flow",
                "original_solver_rerun" => false,
                "full_dispatch_sufficiency_claim" => false,
                "variable_flow_impossibility_claim" => false,
                "iis_replay_scope" => "IIS record retained; its two rows checked against independent parcel replay, without rerunning Gurobi",
            ),
        ),
    )
    for (dir, _, names) in walkdir(stage), name in names
        p = joinpath(dir, name)
        filesize(p) <= 5 * 1024^2 || error("单文件超过仓库门槛")
        text = read(p, String)
        any(
            occursin(needle, text) for needle in (
                "C:" * "\\Users\\",
                "D:" * "\\Work\\",
                "C:" * "/Users/",
                "D:" * "/Work/",
                "WLS" * "SECRET=",
            )
        ) && error("公开温区包含本机路径或凭据")
    end
    write(joinpath(stage, "artifacts.toml"), PR.r7_text(Dict("files" => files(stage))))
    mv(stage, out)
    check(out; replay = true)
end

function check(folder; replay = false)
    expected = TOML.parsefile(joinpath(folder, "artifacts.toml"))["files"]
    actual = files(folder)
    delete!(actual, "artifacts.toml")
    actual == expected || error("温区封存字节或集合改变")
    scope = TOML.parsefile(joinpath(folder, "scope.toml"))
    scope["schema"] == "r9-handoff-evidence-v1" &&
    !scope["original_solver_rerun"] &&
    !scope["full_dispatch_sufficiency_claim"] &&
    !scope["variable_flow_impossibility_claim"] || error("温区证据范围被扩大")
    if replay
        parent = mktempdir(joinpath(ROOT, "tmp"); prefix = "r9-handoff-replay-", cleanup = false)
        dest = joinpath(parent, "relocated")
        cp(folder, dest)
        m = Module(gensym(:HandoffEvidenceReplay))
        Base.include(m, joinpath(dest, "report-source.jl"))
        lib = Base.invokelatest(getfield, m, :R9HandoffEvidence)
        f = Base.invokelatest(getfield, lib, :evaluate)
        got = Base.invokelatest(f, dest)
        saved = Objects.parseobject(
            folder,
            TOML.parsefile(joinpath(folder, "result-index.toml"))["result_sha256"],
        )
        isequal(got, saved) || error("移位温区原值重验不同")
        println("Handoff frozen numerical replay passed: ", relpath(dest, ROOT))
    end
    println("Handoff artifact hashes passed: ", length(expected))
    true
end
end

if abspath(PROGRAM_FILE) == @__FILE__
    if length(ARGS) == 5 && ARGS[1] == "freeze"
        R9HandoffEvidence.freeze(abspath.(ARGS[2:5])...)
    elseif length(ARGS) in (2, 3) &&
           ARGS[1] == "check" &&
           (length(ARGS) == 2 || ARGS[3] == "--replay")
        R9HandoffEvidence.check(abspath(ARGS[2]); replay = length(ARGS) == 3)
    else
        error(
            "usage: r9_handoff_evidence.jl freeze BASELINE CANDIDATE IIS NEW_EVIDENCE | check EVIDENCE [--replay]",
        )
    end
end
