include("r5_benders_report_tables.jl")

"""从原失败点与新原值独立核对状态、诊断证书和全方法费用；不重新求解。"""
function r5_benders_status_tables(dir, input; root = normpath(joinpath(@__DIR__, "..")))
    rules=input.rules
    tables=Dict{String,Vector{NamedTuple}}(
        "status-probes.csv"=>NamedTuple[],
        "before-after.csv"=>NamedTuple[],
    )
    for p in rules["probes"]
        r=TOML.parsefile(joinpath(dir, "probes", p["id"]*".toml"))
        c=R5RiskCase(r["case"])
        c.sha256==r["case_sha256"]==input.cases[p["case"]].sha256||error("探测输入变化")
        r["entry"]==p&&r["source"]==input.sources[p["source_id"]]||error("原失败点变化")
        bounds=PaperRebuild.r5_benders_bounds(c, p["scenario"])
        r["bounded_objective"]==Dict(
            "lower"=>bounds.lower_cost,
            "upper"=>bounds.upper_cost,
            "finite_box"=>all(isfinite(l)&&isfinite(u) for (l, u) in values(bounds.box)),
        )||error("有限盒解释不同")
        Set(keys(r["results"]))⊆Set(("0", "1"))||error("未声明的求解器试探")
        samples=collect(values(r["results"]))
        haskey(r, "diagnostic")&&push!(samples, r["diagnostic"])
        for s in samples
            s["first_stage"]==r["source"]["first_stage"]&&s["branch"]==p["branch"]&&s["scenario"]==p["scenario"]||error(
                "配对点改变",
            )
            s["source_hashes_at_solve"]==rules["science_sha256"]&&s["source_unchanged"]||error(
                "探测科学版本不同",
            )
            check=validate_r5_benders_subproblem(c, s)
            r5_benders_evidence_hash(check)==r5_benders_evidence_hash(s["validation"])||error(
                "探测验收改变",
            )
        end
        d=get(r, "diagnostic", Dict())
        dv=get(d, "validation", Dict())
        trusted=get(dv, "kkt_pass", false)
        support=trusted ? r5_benders_cut(c, d; arithmetic = :rational_box)["source_value"] : NaN
        push!(
            tables["status-probes.csv"],
            (;
                probe_id = p["id"],
                case = p["case"],
                source_id = p["source_id"],
                case_sha256 = c.sha256,
                scenario = p["scenario"],
                branch = p["branch"],
                original_status = r["source"]["status"],
                dr1_status = get(get(r["results"], "1", Dict()), "status", "not_executed"),
                dr0_status = get(get(r["results"], "0", Dict()), "status", "not_executed"),
                finite_cost_box = r["bounded_objective"]["finite_box"],
                cost_lower_USD = bounds.lower_cost,
                cost_upper_USD = bounds.upper_cost,
                diagnostic_status = get(d, "status", "not_executed"),
                diagnostic_kkt = trusted,
                diagnostic_objective = get(d, "solver_objective", NaN),
                certified_diagnostic_lower = support,
                positive_infeasibility_certificate = trusted&&support>1e-8,
                elapsed_sec = r["elapsed_sec"],
                budget_overrun_sec = r["budget_overrun_sec"],
            ),
        )
    end
    for e in rules["runs"]
        loaded=r5_benders_read_witness(joinpath(dir, "witnesses", e["id"]))
        c, r=loaded.case, loaded.result
        c.sha256==input.cases[e["case"]].sha256&&r["source_hashes_at_solve"]==rules["science_sha256"]||error(
            "新完整方法输入/来源不同",
        )
        spec=r5_benders_study_spec(input.original_rules, Dict("route"=>"critical"))
        r["spec"]==PaperRebuild.r5_benders_spec(spec)||error("分解规则改变")
        ref=input.original_rules["references"][e["case"]]
        reference=TOML.parsefile(joinpath(root, split(ref["witness"], '/')...))
        entry=merge(e, Dict("route"=>"critical", "solver"=>"gurobi_subproblem_DR0"))
        for (file, rows) in r5_benders_report_tables(c, r, entry, reference)
            append!(get!(tables, file, NamedTuple[]), rows)
        end
        old=r5_benders_read_witness(
            joinpath(root, "results", "summaries", "r5-benders", "witnesses", e["parent_id"]),
        )
        ov=old.result["validation"]
        nv=r["validation"]
        push!(
            tables["before-after.csv"],
            (;
                case = e["case"],
                parent_id = e["parent_id"],
                record_id = e["id"],
                original_run_id = old.result["run_id"],
                new_run_id = r["run_id"],
                original_status = old.result["status"],
                new_status = r["status"],
                original_candidate = ov["model_pass"],
                new_candidate = nv["model_pass"],
                original_cost_complete = old.result["cost_optimization_complete"],
                new_cost_complete = r["cost_optimization_complete"],
                original_cost = ov["upper_bound"],
                new_cost = nv["upper_bound"],
                original_iterations = length(old.result["iterations"]),
                new_iterations = length(r["iterations"]),
            ),
        )
    end
    tables
end
