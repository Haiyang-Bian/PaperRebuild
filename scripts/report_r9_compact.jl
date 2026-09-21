# 仅读取原数值与原案例元数据，不重新优化。
module R9CompactReport
using TOML, CSV, SHA
include("r9_seeded_study.jl")
include("seal_r9_seeded.jl")
const S=R9SeededStudy
const E=R9SeededEvidence

"""拒绝未声明的配对变化：本批只允许装配表示、日志观测和比较说明改变。"""
function check_protocol(a, b)
    a["cases"]==b["cases"] || error("Different mathematical cases")
    allowed=Set(["representation", "solver_log", "comparison_scope"])
    union(Set(keys(a["protocol"])), allowed)==union(Set(keys(b["protocol"])), allowed) ||
        error("Undeclared protocol fields")
    for key in keys(a["protocol"])
        key in allowed && continue
        a["protocol"][key]==b["protocol"][key] || error("Undeclared protocol change: $key")
    end
    get(a["protocol"], "representation", "original")=="original" || error("Wrong original model")
    b["protocol"]["representation"]=="r9_compact_v1" && b["protocol"]["solver_log"] ||
        error("Wrong comparison model")
    true
end

"""按原情景经验概率求实际光伏电量，MW乘h得MWh；不使用最坏费用分布，也不把其他DER当光伏。"""
function pv_energy(scenarios, result)
    total=0.0
    for scenario in scenarios
        d=scenario["case"]
        values=result["scenarios"][scenario["id"]]["values"]["P_DER"]
        length(values)==length(d["devices"]) || error("Device/value dimensions")
        energy=sum(
            (sum(values[g]) for (g, dev) in enumerate(d["devices"]) if dev["kind"]=="PV");
            init = 0.0,
        )*d["dt_h"]
        total+=scenario["probability"]*energy
    end
    total
end

function csv_or_header(path, rows, header)
    isempty(rows) ? write(path, header*"\n") : CSV.write(path, rows)
end

"""核对配对协议后提取原候选、费用界、阶段耗时及光伏/备用原值；不把模型表示变化解释为物理收益。"""
function report(common, oldfreeze, newfreeze, oldevidence, newevidence, out)
    ispath(out) && error("Preserve previous comparison")
    a=TOML.parsefile(joinpath(oldfreeze, "manifest.toml"))
    b=TOML.parsefile(joinpath(newfreeze, "manifest.toml"))
    check_protocol(a, b)
    E.check(common, oldfreeze, oldevidence; replay = false)
    E.check(common, newfreeze, newevidence; replay = false)
    bundle=S.loadfreeze(common, newfreeze)
    rows=NamedTuple[]
    timings=NamedTuple[]
    commitments=NamedTuple[]
    residuals=NamedTuple[]
    for scheme in b["protocol"]["schemes"]
        c=S.C.riskcase(bundle.state, scheme)
        scenarios=c.data["commitment"]["scenarios"]
        for (representation, evidence) in
            (("original", oldevidence), ("r9_compact_v1", newevidence))
            path=joinpath(evidence, scheme)
            status=TOML.parsefile(joinpath(path, "status.toml"))
            raw=isdir(joinpath(path, "run")) ? S.read_numeric(joinpath(path, "run")) : nothing
            r=raw===nothing ? Dict{String,Any}() : raw.result
            v=raw===nothing ? Dict{String,Any}() : raw.validation
            checked=all(get(v, k, false) for k in ("model_pass", "risk_pass", "cost_pass"))
            has=get(r, "has_candidate", false)
            run_id=get(r, "run_id", "not_created/"*scheme*"/"*representation)
            reserve_peak=NaN
            pv_expected=NaN
            if has
                x=r["first_stage"]
                reserve_peak=maximum(abs(q) for key in ("R_up_MW", "R_down_MW") for q in x[key])
                for t in eachindex(x["P_DA_MW"])
                    push!(
                        commitments,
                        (;
                            scheme,
                            representation,
                            hour = t,
                            P_DA_MW = x["P_DA_MW"][t],
                            R_up_MW = x["R_up_MW"][t],
                            R_down_MW = x["R_down_MW"][t],
                            checked,
                            run_id,
                        ),
                    )
                end
                pv_expected=pv_energy(scenarios, r)
            end
            push!(
                rows,
                (;
                    scheme,
                    representation,
                    status = status["status"],
                    has_candidate = has,
                    checked,
                    cost_CNY = checked ? v["worst_net_cost"] : NaN,
                    lower_CNY = get(r, "solver_objective_bound", NaN),
                    valid_bound = get(v, "valid_bound", false) &&
                                  abs(get(r, "solver_objective_bound", Inf))<1e90,
                    relative_gap = get(v, "relative_gap", NaN),
                    optimality_pass = get(v, "optimality_pass", false),
                    elapsed_sec = status["elapsed_sec"],
                    budget_pass = status["budget_pass"],
                    reserve_peak_MW = reserve_peak,
                    PV_empirical_energy_MWh = pv_expected,
                    worst_comfort_probability = get(v, "worst_violation_probability", NaN),
                    run_id,
                ),
            )
            for (stage, seconds) in sort(collect(get(r, "timings", Dict())); by = first)
                push!(timings, (; scheme, representation, stage, seconds, run_id))
            end
            for key in ("preparation_sec", "save_and_read_sec")
                haskey(status, key) && push!(
                    timings,
                    (; scheme, representation, stage = key, seconds = status[key], run_id),
                )
            end
            for (group, q) in sort(collect(get(v, "groups", Dict())); by = first)
                push!(
                    residuals,
                    (;
                        scheme,
                        representation,
                        group,
                        count = q["count"],
                        failed = q["failed"],
                        normalized = q["max_normalized"],
                        run_id,
                    ),
                )
            end
        end
    end
    mkpath(out)
    CSV.write(joinpath(out, "summary.csv"), rows)
    csv_or_header(
        joinpath(out, "timings.csv"),
        timings,
        "scheme,representation,stage,seconds,run_id",
    )
    csv_or_header(
        joinpath(out, "commitments.csv"),
        commitments,
        "scheme,representation,hour,P_DA_MW,R_up_MW,R_down_MW,checked,run_id",
    )
    csv_or_header(
        joinpath(out, "residuals.csv"),
        residuals,
        "scheme,representation,group,count,failed,normalized,run_id",
    )
    cp(@__FILE__, joinpath(out, "report-source.jl"))
    m=Dict(
        "schema"=>"r9-compact-comparison-v1",
        "origin"=>"synthetic",
        "optimization_performed"=>false,
        "old_freeze_sha256"=>E.hashfile(joinpath(oldfreeze, "manifest.toml")),
        "new_freeze_sha256"=>E.hashfile(joinpath(newfreeze, "manifest.toml")),
        "old_evidence_sha256"=>E.hashfile(joinpath(oldevidence, "delivery.toml")),
        "new_evidence_sha256"=>E.hashfile(joinpath(newevidence, "delivery.toml")),
        "common_sha256"=>E.hashfile(joinpath(common, "manifest.toml")),
        "run_ids"=>[r.run_id for r in rows],
        "PV_statistic"=>"empirical_expected_actual_energy_not_worst_distribution",
        "timings_scope"=>"recorded_stages_only; not a complete disjoint partition",
        "comparison_scope"=>b["protocol"]["comparison_scope"],
        "files"=>Dict(p=>E.hashfile(joinpath(out, p)) for p in readdir(out)),
    )
    E.toml(joinpath(out, "comparison-source.toml"), m)
    rows
end
end
if abspath(PROGRAM_FILE)==@__FILE__
    length(ARGS)==6 ||
        error("usage: COMMON OLD_FREEZE NEW_FREEZE OLD_EVIDENCE NEW_EVIDENCE NEW_REPORT")
    R9CompactReport.report(abspath.(ARGS)...)
end
