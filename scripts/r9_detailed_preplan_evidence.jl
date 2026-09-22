# 由冻结源码重算详细灾前和独立恢复；不调用优化器，不将见证当作各故障最小失供。
module R9DetailedPreplanEvidence
using TOML, SHA, CSV, Dates
include("r9_resilience_evidence.jl")
const Archive = R9ResilienceEvidence
const Objects = Archive.Objects
const ROOT = dirname(@__DIR__)
hashfile(p) = bytes2hex(sha256(read(p)))
files(dir) = Dict(
    replace(relpath(joinpath(d, f), dir), '\\' => '/') => hashfile(joinpath(d, f)) for
    (d, _, fs) in walkdir(dir) for f in fs
)
toml(p, x) = open(io -> TOML.print(io, x; sorted = true), p, "w")
call(lib, name, args...) = Base.invokelatest(Base.invokelatest(getfield, lib, name), args...)
function verify(dir)
    m = TOML.parsefile(joinpath(dir, "files.toml"))
    actual = files(dir)
    delete!(actual, "files.toml")
    actual == m["files"] || error("输入或运行字节/集合改变")
    foreach(p -> Archive.safe(dir, p), keys(actual))
    m
end

function make_tables(input, raw, baseline_csv, baseline_manifest, baseline_index)
    m = verify(input)
    m["schema"] == "r9-detailed-preplan-input-v1" && !m["optimization_performed"] ||
        error("冻结类型错误")
    p = TOML.parsefile(joinpath(input, "protocol.toml"))
    parent = TOML.parsefile(joinpath(input, "parent-files.toml"))
    hashfile(joinpath(input, "parent-files.toml")) == p["parent_manifest_sha256"] ||
        error("父输入不同")
    for file in ("normal.toml", "planning.toml", "construction.toml")
        hashfile(joinpath(input, file)) == parent["files"][file] || error("物理输入改变")
    end
    oldmanifest = TOML.parsefile(baseline_manifest)["files"]
    hashfile(baseline_csv) == oldmanifest["comparison.csv"] || error("原聚合规划的冻结比较表不同")
    hashfile(baseline_index) == oldmanifest["index.toml"] || error("原基准索引不同")
    TOML.parsefile(baseline_index)["input"]["files.toml"] == p["parent_manifest_sha256"] ||
        error("新旧模型并非同一原始物理输入")
    oldrows = collect(CSV.File(baseline_csv))
    rows, comparison = NamedTuple[], NamedTuple[]
    construction = TOML.parsefile(joinpath(input, "construction.toml"))
    for mode in p["modes"]
        dir = joinpath(raw, mode)
        verify(dir)
        protocol = TOML.parsefile(joinpath(dir, "protocol.toml"))
        protocol["input_manifest_sha256"] == hashfile(joinpath(input, "files.toml")) &&
        protocol["mode"] == mode &&
        protocol["no_warm_start_injected"] &&
        !protocol["whole_fault_claim"] || error("运行协议或候选来源改变")
        all(m["files"]["code/"*key] == h for (key, h) in protocol["source_hashes"]) ||
            error("运行没有使用冻结科学源码")
        native = Archive.frozen_read(joinpath(dir, "primary"))
        x = native.data
        isequal(x.case.normal.data, TOML.parsefile(joinpath(input, "normal.toml"))) &&
        isequal(x.case.specification, TOML.parsefile(joinpath(input, "planning.toml"))) &&
        isequal(x.spec, TOML.parsefile(joinpath(input, mode * "-spec.toml"))) ||
            error("主问题输入不同")
        lib = Base.invokelatest(getfield, native.mod, :FrozenR9Detailed)
        r, q = x.result, x.validation
        execution = TOML.parsefile(joinpath(dir, "execution.toml"))
        execution["budget_pass"] == (execution["total_wall_sec"] <= p["budget_sec"]) ||
            error("预算摘要错误")
        cost = get(q, "normal_cost", NaN)
        worst = get(q, "witness_worst_MWh", Float64[])
        push!(
            rows,
            (
                mode = mode,
                stage = "primary",
                run_id = r["run_id"],
                status = r["status"],
                model_pass = q["model_pass"],
                normal_cost_CNY = cost,
                penalty_CNY = get(q, "penalty_cost", NaN),
                solver_objective = get(r, "solver_objective", NaN),
                objective_unit = "CNY",
                lower_bound = get(r, "objective_lower_bound", NaN),
                relative_gap = get(q, "relative_gap", NaN),
                conditional_gap_pass = q["objective_optimality_pass"],
                critical_loss_MWh = isempty(worst) ? NaN : maximum(worst),
                threshold_pass = q["selected_threshold_witness_pass"],
                handoff_necessary_pass = false,
                whole_method_sec = execution["total_wall_sec"],
                budget_pass = execution["budget_pass"],
            ),
        )
        length(execution["stages"]) == length(p["fault_ids"]) || error("独立阶段缺少显式记录")
        carrier = call(lib, :r9_detailed_preplan_check, x.case, x.spec)
        for (i, id) in enumerate(p["fault_ids"])
            stage = execution["stages"][i]
            stage["fault_id"] == id || error("阶段顺序改变")
            if !stage["attempted"]
                push!(
                    rows,
                    (
                        mode = mode,
                        stage = "detailed-" * id,
                        run_id = "",
                        status = stage["status"],
                        model_pass = false,
                        normal_cost_CNY = cost,
                        penalty_CNY = NaN,
                        solver_objective = NaN,
                        objective_unit = "MWh",
                        lower_bound = NaN,
                        relative_gap = NaN,
                        conditional_gap_pass = false,
                        critical_loss_MWh = NaN,
                        threshold_pass = false,
                        handoff_necessary_pass = false,
                        whole_method_sec = execution["total_wall_sec"],
                        budget_pass = execution["budget_pass"],
                    ),
                )
                continue
            end
            q["model_pass"] || error("未合格主问题混入独立恢复")
            pair = (event = 1, fault = construction["pilot_faults"][id])
            ev = call(
                lib,
                :r7_linked_event,
                carrier,
                x.spec["linked_spec"],
                r["master"]["normal"],
                pair,
            )
            rec = Archive.frozen_read(joinpath(dir, "detailed-" * id)).data
            rec.case.sha256 == ev.case.sha256 && isequal(rec.spec, ev.spec) ||
                error("恢复初态/流量不同")
            handoff = call(lib, :r9_handoff_temperature_check, ev.case, ev.spec)
            isequal(handoff, TOML.parsefile(joinpath(dir, "handoff-" * id * ".toml"))) ||
                error("温区预检失步")
            handoff["necessary_condition_pass"] == stage["handoff_necessary_pass"] ||
                error("温区阶段摘要错误")
            z, v = rec.result, rec.validation
            loss = get(v, "loss_MWh", NaN)
            v["model_pass"] == stage["model_pass"] &&
            isequal(loss, stage["loss_MWh"]) &&
            z["status"] == stage["status"] || error("恢复阶段摘要不同")
            lb = get(z, "lower_bound_MWh", NaN)
            gap = isfinite(loss) && isfinite(lb) ? (loss - lb) / max(1, abs(loss)) : NaN
            push!(
                rows,
                (
                    mode = mode,
                    stage = "detailed-" * id,
                    run_id = z["run_id"],
                    status = z["status"],
                    model_pass = v["model_pass"],
                    normal_cost_CNY = cost,
                    penalty_CNY = NaN,
                    solver_objective = get(z, "solver_objective_MWh", NaN),
                    objective_unit = "MWh",
                    lower_bound = lb,
                    relative_gap = gap,
                    conditional_gap_pass = v["model_pass"] && -1e-6 <= gap <= 1e-4,
                    critical_loss_MWh = loss,
                    threshold_pass = v["model_pass"] &&
                                     loss <= p["loss_limit_MWh"] + 1e-6 * (1 + p["loss_limit_MWh"]),
                    handoff_necessary_pass = handoff["necessary_condition_pass"],
                    whole_method_sec = execution["total_wall_sec"],
                    budget_pass = execution["budget_pass"],
                ),
            )
            old = only(filter(a -> a.stage == "detailed-" * id, oldrows))
            push!(
                comparison,
                (
                    mode = mode,
                    fault = id,
                    old_normal_cost_CNY = old.baseline_normal_cost_CNY,
                    new_normal_cost_CNY = cost,
                    old_detailed_loss_MWh = old.baseline_loss_MWh,
                    new_detailed_loss_MWh = loss,
                    loss_reduction_MWh = v["model_pass"] && old.baseline_model_pass ?
                                         old.baseline_loss_MWh - loss : NaN,
                    old_run_id = old.baseline_run_id,
                    new_run_id = z["run_id"],
                    new_model_pass = v["model_pass"],
                    fixed_inputs_shared = true,
                ),
            )
        end
    end
    Dict("summary.csv" => Objects.csvbytes(rows), "comparison.csv" => Objects.csvbytes(comparison))
end

function freeze(input, raw, baseline, out)
    ispath(out) && error("不覆盖详细灾前证据")
    tables = make_tables(
        input,
        raw,
        joinpath(baseline, "comparison.csv"),
        joinpath(baseline, "artifacts.toml"),
        joinpath(baseline, "index.toml"),
    )
    stage = out * ".writing"
    ispath(stage) && error("封存暂存目录已存在")
    mkpath(joinpath(stage, "objects"))
    index = Dict(
        "schema" => "r9-detailed-preplan-evidence-v1",
        "utc" => string(now(UTC)),
        "input" => Objects.pack(stage, input),
        "raw" => Objects.pack(stage, raw),
        "baseline_artifacts_sha256" => hashfile(joinpath(baseline, "artifacts.toml")),
        "optimization_performed" => false,
        "whole_fault_certificate" => false,
        "origin" => "synthetic replacement inputs on author-scale topology",
    )
    toml(joinpath(stage, "index.toml"), index)
    cp(joinpath(baseline, "comparison.csv"), joinpath(stage, "baseline-comparison.csv"))
    cp(joinpath(baseline, "artifacts.toml"), joinpath(stage, "baseline-artifacts.toml"))
    cp(joinpath(baseline, "index.toml"), joinpath(stage, "baseline-index.toml"))
    for (name, bytes) in tables
        write(joinpath(stage, name), bytes)
    end
    cp(@__FILE__, joinpath(stage, "report-source.jl"))
    for name in ("r9_resilience_evidence.jl", "r9_fixed_evidence.jl")
        cp(joinpath(@__DIR__, name), joinpath(stage, name))
    end
    toml(joinpath(stage, "artifacts.toml"), Dict("files" => files(stage)))
    mv(stage, out)
    check(out; replay = true)
end

function check(folder; replay = false)
    expected = TOML.parsefile(joinpath(folder, "artifacts.toml"))["files"]
    actual = files(folder)
    delete!(actual, "artifacts.toml")
    expected == actual || error("详细灾前封存字节改变")
    index = TOML.parsefile(joinpath(folder, "index.toml"))
    index["schema"] == "r9-detailed-preplan-evidence-v1" &&
    !index["optimization_performed"] &&
    !index["whole_fault_certificate"] || error("证据范围改变")
    hashfile(joinpath(folder, "baseline-artifacts.toml")) == index["baseline_artifacts_sha256"] ||
        error("原基准出处改变")
    if replay
        root = isdir(joinpath(ROOT, "tmp")) ? joinpath(ROOT, "tmp") : tempdir()
        dest = mktempdir(root; prefix = "r9-detailed-replay-", cleanup = false)
        for name in ("input", "raw")
            Archive.extract(folder, index[name], joinpath(dest, name))
        end
        m = Module(gensym(:R9DetailedReport))
        Base.include(m, joinpath(folder, "report-source.jl"))
        lib = Base.invokelatest(getfield, m, :R9DetailedPreplanEvidence)
        tables = call(
            lib,
            :make_tables,
            joinpath(dest, "input"),
            joinpath(dest, "raw"),
            joinpath(folder, "baseline-comparison.csv"),
            joinpath(folder, "baseline-artifacts.toml"),
            joinpath(folder, "baseline-index.toml"),
        )
        for (name, bytes) in tables
            bytes == read(joinpath(folder, name)) || error("详细灾前表格与原值失步")
        end
        println("Detailed preplan frozen-source replay passed: ", relpath(dest, ROOT))
    end
    println("Detailed preplan artifact hashes passed: ", length(expected))
    true
end
end

if abspath(PROGRAM_FILE) == @__FILE__
    if length(ARGS) == 5 && ARGS[1] == "freeze"
        R9DetailedPreplanEvidence.freeze(abspath.(ARGS[2:5])...)
    elseif length(ARGS) in (2, 3) &&
           ARGS[1] == "check" &&
           (length(ARGS) == 2 || ARGS[3] == "--replay")
        R9DetailedPreplanEvidence.check(abspath(ARGS[2]); replay = length(ARGS) == 3)
    else
        error(
            "usage: r9_detailed_preplan_evidence.jl freeze INPUT RAW BASELINE_FAULT_EVIDENCE NEW_EVIDENCE | check EVIDENCE [--replay]",
        )
    end
end
