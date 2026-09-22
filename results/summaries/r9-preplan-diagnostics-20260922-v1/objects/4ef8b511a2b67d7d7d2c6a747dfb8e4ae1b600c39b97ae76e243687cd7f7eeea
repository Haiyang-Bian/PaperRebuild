# 同一冻结输入的两项独立诊断：最小最坏失供、CHP1事件全开时的原罚费目标。
# 不改正式4A/4B/4C，不向它们注入候选，不将失供下界当成正常费用下界。
const LOSS_AUDIT_STARTED = time()
using PaperRebuild, JuMP, Gurobi, TOML, SHA, UUIDs
include("r9_preplan_study.jl")
const PR = PaperRebuild

function main(input, out)
    ispath(out) && error("不覆盖已有诊断")
    x = R9PreplanStudy.readinput(input)
    c = x.case
    s = TOML.parsefile(joinpath(input, "penalty-spec.toml"))
    sources =
        merge(R9PreplanStudy.science(), Dict("scripts/audit_r9_preplan_loss_floor.jl" => @__FILE__))
    hashes = Dict(k => R9PreplanStudy.hashfile(v) for (k, v) in sources)
    mkpath(out)
    for (p, file) in sources
        dest = joinpath(out, "code", p)
        mkpath(dirname(dest))
        cp(file, dest)
    end
    protocol = Dict(
        "schema" => "r9-preplan-loss-audit-v1",
        "input_manifest_sha256" => R9PreplanStudy.hashfile(joinpath(input, "files.toml")),
        "budget_sec" => 180.0,
        "source_hashes" => hashes,
        "order" => ["minimum_selected_worst_loss", "penalty_with_CHP1_event_on"],
        "stage_deadlines_sec" => [100.0, 165.0],
        "fixed_case_and_selected_faults" => true,
        "diagnostic_not_formal_method" => true,
        "full_fault_certificate" => false,
    )
    write(joinpath(out, "protocol.toml"), PR.r7_text(protocol))
    opt = optimizer_with_attributes(
        Gurobi.Optimizer,
        "OutputFlag" => 0,
        "Threads" => 1,
        "DualReductions" => 0,
        "FeasibilityTol" => 1e-9,
        "IntFeasTol" => 1e-9,
        "OptimalityTol" => 1e-9,
        "MIPGap" => 1e-4,
    )
    for (kind, offset) in zip(protocol["order"], protocol["stage_deadlines_sec"])
        stop = LOSS_AUDIT_STARTED + offset
        start = time()
        r = Dict{String,Any}(
            "kind" => kind,
            "status" => "budget_exhausted",
            "run_id" => "r9-loss-audit-" * string(uuid4()),
            "input_manifest_sha256" => protocol["input_manifest_sha256"],
            "source_hashes" => hashes,
        )
        if time() < stop
            b = build_r9_preplan(c, s; optimizer = opt)
            if kind == "minimum_selected_worst_loss"
                @objective(b.model, Min, sum(b.ζ))
                r["objective_kind"] = "minimum_selected_event_worst_loss_MWh"
            else
                ev = only(c.specification["events"])
                win = ev["event_start"]:(ev["event_start"]+ev["periods"]-1)
                u = b.chp_variables["CHP1"]["u_CHP"]
                for t in win
                    @constraint(b.model, u[t] == 1)
                end
                r["pinned_event_steps"] = collect(win)
                r["objective_kind"] = "normal_cost_plus_worst_loss_penalty_CNY"
            end
            r["build_sec"] = time() - start
            if time() < stop
                set_silent(b.model)
                set_time_limit_sec(b.model, stop - time())
                optimize!(b.model)
                r["status"] = string(termination_status(b.model))
                r["primal_status"] = string(primal_status(b.model))
                try
                    lb = objective_bound(b.model)
                    isfinite(lb) && (r["objective_lower_bound"] = lb)
                catch err
                    r["bound_unavailable"] = string(typeof(err))
                end
                if has_values(b.model)
                    r["solver_objective"] = objective_value(b.model)
                    v = PR.r9_preplan_snapshot(b, c, s, r["run_id"])
                    r["master"] = v.master
                    r["epigraph_MWh"] = v.epigraph_MWh
                    r["validation"] = PR.r7_planning_master_check(b.carrier, v.master)
                    r["normal_cost_CNY"] = value(b.normal_cost)
                    r["selected_worst_loss_MWh"] = sum(v.epigraph_MWh)
                    r["objective_replay"] =
                        kind == "minimum_selected_worst_loss" ? sum(v.epigraph_MWh) :
                        r["normal_cost_CNY"] + s["penalty_MWh"] * sum(v.epigraph_MWh)
                    r["epigraph_pass"] = all(
                        v.epigraph_MWh[w["event"]] + 1e-6 * (1 + abs(w["witness_loss_MWh"])) >=
                        w["witness_loss_MWh"] for w in v.master["witnesses"]
                    )
                    r["objective_pass"] =
                        abs(r["solver_objective"] - r["objective_replay"]) <=
                        1e-6 * max(1.0, abs(r["objective_replay"]))
                    if haskey(r, "objective_lower_bound")
                        r["relative_gap"] =
                            (r["objective_replay"] - r["objective_lower_bound"]) /
                            max(1.0, abs(r["objective_replay"]))
                    end
                    r["pin_pass"] =
                        kind != "penalty_with_CHP1_event_on" || all(
                            abs(
                                PR.r7_unpack(v.master["normal"]["chp_values"]["CHP1"], "u_CHP")[t] -
                                1,
                            ) <= 1e-6 for t in r["pinned_event_steps"]
                        )
                end
            end
        end
        r["elapsed_sec"] = time() - start
        write(joinpath(out, kind * ".toml"), PR.r7_text(r))
        println(
            kind,
            " status=",
            r["status"],
            " objective=",
            get(r, "solver_objective", NaN),
            " bound=",
            get(r, "objective_lower_bound", NaN),
            " normal_cost=",
            get(r, "normal_cost_CNY", NaN),
        )
        flush(stdout)
    end
    all(R9PreplanStudy.hashfile(sources[k]) == h for (k, h) in hashes) || error("诊断中源码改变")
    write(
        joinpath(out, "audit.toml"),
        PR.r7_text(
            Dict(
                "files" => R9PreplanStudy.filehashes(out),
                "total_wall_sec" => time() - LOSS_AUDIT_STARTED,
                "budget_pass" => time() - LOSS_AUDIT_STARTED <= 180.0,
                "whole_fault_claim" => false,
            ),
        ),
    )
end
length(ARGS) == 2 || error("usage: audit_r9_preplan_loss_floor.jl FROZEN_INPUT NEW_AUDIT")
main(abspath(ARGS[1]), abspath(ARGS[2]))
