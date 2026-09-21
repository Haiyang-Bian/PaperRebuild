module R9DetailedPreplanStudy
const STARTED = time()
using PaperRebuild, JuMP, TOML, SHA, Dates, UUIDs
include("r9_preplan_study.jl")
const Old = R9PreplanStudy
const PR = PaperRebuild
const ROOT = dirname(@__DIR__)
hashfile(p) = bytes2hex(sha256(read(p)))
filehashes(folder) = Dict(
    replace(relpath(joinpath(d, f), folder), '\\' => '/') => hashfile(joinpath(d, f)) for
    (d, _, fs) in walkdir(folder) for f in fs
)
science() = merge(
    Old.science(),
    PR.r9_detailed_preplan_science_paths(),
    Dict(
        "scripts/r9_detailed_preplan_study.jl" => @__FILE__,
        "scripts/run_r9_detailed_preplan.jl" =>
            joinpath(ROOT, "scripts/run_r9_detailed_preplan.jl"),
        "tools/solvers/Project.toml" => joinpath(ROOT, "tools/solvers/Project.toml"),
        "tools/solvers/Manifest.toml" => joinpath(ROOT, "tools/solvers/Manifest.toml"),
    ),
)

function normal_flows(c)
    d = c.normal.data
    Dict(
        PR.r7_planning_pair_key(p) => begin
            e = c.specification["events"][p.event]
            window = e["event_start"]:(e["event_start"]+e["periods"]-1)
            Dict(
                "m_pipe" => reduce(
                    vcat,
                    [permutedims(a["normal_flow_kg_s"][window]) for a in d["heat"]["pipes"]],
                ),
                "m_source" => reduce(
                    vcat,
                    [permutedims(a[window]) for a in d["heat"]["source_flow_kg_s"]],
                ),
                "m_load" =>
                    reduce(vcat, [permutedims(a[window]) for a in d["heat"]["load_flow_kg_s"]]),
            )
        end for p in PR.r7_planning_pairs(c)
    )
end

function freeze(out)
    ispath(out) && error("不覆盖详细灾前输入")
    p = TOML.parsefile(joinpath(ROOT, "configs/r9/detailed-preplan-study.toml"))
    parent = joinpath(ROOT, p["parent_input"])
    old = Old.readinput(parent; current_code = false)
    hashfile(joinpath(parent, "files.toml")) == p["parent_manifest_sha256"] ||
        error("父输入身份不同")
    c = old.case
    pairs = PR.r9_preplan_pairs(TOML.parsefile(joinpath(parent, "penalty-spec.toml")))
    p["fault_ids"] == old.protocol["fault_ids"] || error("比较故障改变")
    flows = normal_flows(c)
    stage = out * ".writing-" * string(uuid4())
    mkpath(stage)
    for f in ("normal.toml", "planning.toml", "construction.toml")
        cp(joinpath(parent, f), joinpath(stage, f))
    end
    cp(joinpath(parent, "files.toml"), joinpath(stage, "parent-files.toml"))
    write(joinpath(stage, "protocol.toml"), PR.r7_text(p))
    for mode in p["modes"]
        spec = r9_detailed_preplan_spec(
            c;
            mode,
            pairs,
            flows,
            penalty_MWh = p["penalty_CNY_MWh"],
            substeps = p["substeps"],
            limits_MWh = fill(p["loss_limit_MWh"], length(c.specification["events"])),
        )
        write(joinpath(stage, mode * "-spec.toml"), PR.r7_text(spec))
    end
    for (name, file) in science()
        target = joinpath(stage, "code", name)
        mkpath(dirname(target))
        cp(file, target)
    end
    m = Dict(
        "schema" => "r9-detailed-preplan-input-v1",
        "utc" => string(now(UTC)),
        "files" => filehashes(stage),
        "code" => sort(collect(keys(science()))),
        "optimization_performed" => false,
        "parent_manifest_sha256" => p["parent_manifest_sha256"],
    )
    write(joinpath(stage, "files.toml"), PR.r7_text(m))
    mv(stage, out)
    readinput(out)
    println("Detailed input frozen sha256=", hashfile(joinpath(out, "files.toml")))
end

function readinput(folder; current_code = true)
    m = TOML.parsefile(joinpath(folder, "files.toml"))
    m["schema"] == "r9-detailed-preplan-input-v1" && !m["optimization_performed"] ||
        error("冻结版本错误")
    actual = filehashes(folder)
    delete!(actual, "files.toml")
    actual == m["files"] && all(Old.safe, keys(actual)) || error("详细输入字节/集合改变")
    p = TOML.parsefile(joinpath(folder, "protocol.toml"))
    hashfile(joinpath(folder, "parent-files.toml")) ==
    m["parent_manifest_sha256"] ==
    p["parent_manifest_sha256"] || error("父清单不一致")
    parent = TOML.parsefile(joinpath(folder, "parent-files.toml"))
    for f in ("normal.toml", "planning.toml", "construction.toml")
        hashfile(joinpath(folder, f)) == parent["files"][f] || error("原物理数据改变")
    end
    if current_code
        Set(keys(science())) == Set(m["code"]) || error("科学源码集合改变")
        all(hashfile(file) == m["files"]["code/"*name] for (name, file) in science()) ||
            error("源码改变，须另冻结版本")
    end
    c = load_r7_planning_case(joinpath(folder, "normal.toml"), joinpath(folder, "planning.toml"))
    construction = TOML.parsefile(joinpath(folder, "construction.toml"))
    pairs = [(event = 1, fault = construction["pilot_faults"][id]) for id in p["fault_ids"]]
    flows = normal_flows(c)
    for mode in p["modes"]
        spec = TOML.parsefile(joinpath(folder, mode * "-spec.toml"))
        expected = r9_detailed_preplan_spec(
            c;
            mode,
            pairs,
            flows,
            penalty_MWh = p["penalty_CNY_MWh"],
            substeps = p["substeps"],
            limits_MWh = fill(p["loss_limit_MWh"], length(c.specification["events"])),
        )
        isequal(spec, expected) || error("规格与冻结构造规则不同")
    end
    (; case = c, protocol = p, manifest = m)
end

function run(folder, out, mode, optimizer; started = STARTED)
    ispath(out) && error("不覆盖详细灾前运行")
    x = readinput(folder)
    c, p = x.case, x.protocol
    mode in p["modes"] || error("未冻结的方法")
    spec = TOML.parsefile(joinpath(folder, mode * "-spec.toml"))
    mkpath(out)
    write(
        joinpath(out, "protocol.toml"),
        PR.r7_text(
            Dict(
                "schema" => "r9-detailed-preplan-run-v1",
                "input_manifest_sha256" => hashfile(joinpath(folder, "files.toml")),
                "mode" => mode,
                "budget_sec" => p["budget_sec"],
                "fault_ids" => p["fault_ids"],
                "source_hashes" => Dict(k => hashfile(v) for (k, v) in science()),
                "no_warm_start_injected" => true,
                "whole_fault_claim" => false,
            ),
        ),
    )
    stop = started + p["primary_deadline_sec"]
    println("Primary ", mode, " start elapsed=", time() - started)
    flush(stdout)
    r = solve_r9_detailed_preplan(
        c,
        spec;
        optimizer,
        budget_sec = max(0.0, stop - time()),
        deadline = stop,
    )
    save_r9_detailed_preplan(c, spec, r, joinpath(out, "primary"))
    println(
        "Primary ",
        r["status"],
        " accepted=",
        r["candidate_accepted"],
        " elapsed=",
        time() - started,
    )
    flush(stdout)
    stages = Any[]
    if r["candidate_accepted"]
        carrier = PR.r9_detailed_preplan_check(c, spec)
        pairs = PR.r9_preplan_pairs(spec["base_spec"])
        for (i, pair) in enumerate(pairs)
            allowance = max(
                0.0,
                min(
                    p["recovery_max_sec"],
                    (started + p["recovery_deadline_sec"] - time()) / (length(pairs) - i + 1),
                ),
            )
            if allowance == 0
                push!(
                    stages,
                    Dict(
                        "fault_id" => p["fault_ids"][i],
                        "attempted" => false,
                        "status" => "budget_exhausted",
                    ),
                )
                continue
            end
            at = time()
            ev = PR.r7_linked_event(carrier, spec["linked_spec"], r["master"]["normal"], pair)
            handoff = r9_handoff_temperature_check(
                ev.case,
                ev.spec;
                deadline = started + p["recovery_deadline_sec"],
            )
            rec = solve_r7_transport_recovery(
                ev.case,
                pair.fault,
                ev.spec;
                optimizer,
                budget_sec = max(0.0, allowance - (time() - at)),
                deadline = at + allowance,
            )
            dest = joinpath(out, "detailed-" * p["fault_ids"][i])
            save_r7_transport_recovery(ev.case, ev.spec, rec, dest)
            write(joinpath(out, "handoff-" * p["fault_ids"][i] * ".toml"), PR.r7_text(handoff))
            push!(
                stages,
                Dict(
                    "fault_id" => p["fault_ids"][i],
                    "attempted" => true,
                    "status" => rec["status"],
                    "model_pass" => rec["validation"]["model_pass"],
                    "loss_MWh" => get(rec["validation"], "loss_MWh", NaN),
                    "handoff_necessary_pass" => handoff["necessary_condition_pass"],
                    "elapsed_sec" => time() - at,
                ),
            )
            println(
                p["fault_ids"][i],
                " ",
                rec["status"],
                " model=",
                rec["validation"]["model_pass"],
            )
            flush(stdout)
        end
    else
        append!(
            stages,
            [
                Dict(
                    "fault_id" => id,
                    "attempted" => false,
                    "status" => "primary_candidate_unavailable",
                ) for id in p["fault_ids"]
            ],
        )
    end
    readinput(folder)
    execution = Dict(
        "stages" => stages,
        "total_wall_sec" => time() - started,
        "budget_pass" => time() - started <= p["budget_sec"],
        "whole_fault_claim" => false,
    )
    write(joinpath(out, "execution.toml"), PR.r7_text(execution))
    write(joinpath(out, "files.toml"), PR.r7_text(Dict("files" => filehashes(out))))
end
end

if abspath(PROGRAM_FILE) == @__FILE__
    if length(ARGS) == 2 && ARGS[1] == "freeze"
        R9DetailedPreplanStudy.freeze(abspath(ARGS[2]))
    elseif length(ARGS) == 2 && ARGS[1] == "check"
        R9DetailedPreplanStudy.readinput(abspath(ARGS[2]))
        println("Detailed preplan input checked")
    else
        error(
            "usage: r9_detailed_preplan_study.jl freeze NEW_INPUT | check INPUT; run via run_r9_detailed_preplan.jl",
        )
    end
end
