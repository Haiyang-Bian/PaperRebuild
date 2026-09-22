include("r5_benders_status_rules.jl")
using Dates
root=normpath(joinpath(@__DIR__, ".."))
target=joinpath(root, "configs", "r5", "benders", "status-study.toml")
ispath(target)&&error("不覆盖状态复核规则")
original=joinpath(root, "configs", "r5", "benders", "study.toml")
input=r5_benders_study_inputs(original)
rules=Dict{String,Any}(
    "schema"=>"r5-benders-status-rules-v1",
    "origin"=>"synthetic",
    "frozen_before_optimization"=>true,
    "frozen_utc"=>string(now(UTC)),
    "parent_rules_sha256"=>bytes2hex(sha256(read(original))),
    "science_sha256"=>input.rules["science_sha256"],
    "probe_budget_sec"=>60.0,
    "method_budget_sec"=>600.0,
    "probe_values"=>[1, 0],
    "subproblem_DualReductions"=>0,
    "master_DualReductions"=>1,
    "scope"=>"Five saved ambiguous LP points: fresh models with DualReductions 1 then 0; phase-I only after definite infeasibility. Three full methods change only subproblem DualReductions. No tolerance/model changes, no reference injection, no automatic further retries.",
    "source_url"=>"https://support.gurobi.com/hc/en-us/articles/4402704428177-How-do-I-resolve-the-error-Model-is-infeasible-or-unbounded",
    "runs"=>Dict{String,Any}[],
    "probes"=>Dict{String,Any}[],
)
for file in R5_STATUS_CASES
    parent=splitext(file)[1]*"--critical--gurobi"
    base=joinpath(root, "results", "summaries", "r5-benders", "witnesses", parent)
    path=joinpath(base, "witness.toml")
    w=TOML.parsefile(path)
    push!(
        rules["runs"],
        Dict(
            "id"=>parent*"--dr0",
            "parent_id"=>parent,
            "case"=>file,
            "parent_sha256"=>bytes2hex(sha256(read(path))),
        ),
    )
    bad=Dict{String,Any}[]
    for (rel, hash) in w["source_files_sha256"]
        srcpath=joinpath(base, split(rel, '/')...)
        bytes2hex(sha256(read(srcpath)))==hash||error("旧子问题变动")
        s=TOML.parsefile(srcpath)
        s["status"]=="INFEASIBLE_OR_UNBOUNDED"||continue
        push!(
            bad,
            Dict(
                "case"=>file,
                "source_id"=>s["run_id"],
                "source_sha256"=>hash,
                "scenario"=>s["scenario"],
                "branch"=>s["branch"],
            ),
        )
    end
    sort!(bad; by = p->(p["scenario"], p["source_id"]))
    for (i, p) in enumerate(bad)
        p["id"]=splitext(file)[1]*"--saved-"*string(i)
        push!(rules["probes"], p)
    end
end
write(target, PaperRebuild.r5_market_text(rules))
r5_benders_status_inputs(target)
println("Frozen five identical-point pairs and three full-method subproblem-only status checks.")
