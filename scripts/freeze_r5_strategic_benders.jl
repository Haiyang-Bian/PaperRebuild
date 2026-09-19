include("r5_strategic_benders_study_rules.jl")
using Dates
root = normpath(joinpath(@__DIR__, ".."))
target = joinpath(root, "configs", "r5", "strategic-benders", "study.toml")
ispath(target) && error("不覆盖策略分解冻结规则")
parent = joinpath(root, "configs", "r5", "strategic", "study.toml")
old = TOML.parsefile(parent)
d = Dict{String,Any}(
    "schema"=>"r5-strategic-benders-study-rules-v1",
    "origin"=>"synthetic",
    "frozen_before_optimization"=>true,
    "frozen_utc"=>string(now(UTC)),
    "science_commit"=>readchomp(`git -C $root rev-parse HEAD`),
    "science_sha256"=>PaperRebuild.r5_strategic_benders_science_hashes(),
    "parent_rules_sha256"=>bytes2hex(sha256(read(parent))),
    "budget_sec"=>600.0,
    "master_solver"=>"gurobi",
    "subproblem_solver"=>"highs",
    "oracle_solver"=>"highs",
    "selection"=>"optimistic_primal_dual",
    "market_domain"=>"full_SOS1",
    "reference_injected"=>false,
    "price_caps_imposed"=>false,
    "initialization"=>"empty_cuts_and_critical_set",
    "scope"=>"Synthetic eight inputs times three routes; full market SOS1. Restricted comfort bounds are separate. No out-of-sample or thesis-scale speed claim.",
    "spec"=>Dict(
        "critical_count"=>1,
        "max_iterations"=>200,
        "absolute_gap"=>1e-7,
        "relative_gap"=>1e-6,
        "cut_arithmetic"=>"rational_box",
        "diagnostic_scale"=>1024.0,
    ),
    "files"=>old["files"],
    "references"=>Dict{String,Any}(),
    "runs"=>Dict{String,Any}[],
    "producer_sha256"=>Dict(
        f=>bytes2hex(sha256(read(joinpath(@__DIR__, f)))) for f in R5_SB_PRODUCERS
    ),
)
for file in sort!(collect(keys(old["files"])))
    c = load_r5_strategic_case(joinpath(dirname(parent), file))
    rel = "results/summaries/r5-strategic/witnesses/"*splitext(file)[1]*"-sos1.toml"
    path = joinpath(root, split(rel, '/')...)
    w = TOML.parsefile(path)
    R5StrategicCase(w["case"]).sha256 == c.sha256 || error("后置参考输入不同")
    d["references"][file] = Dict(
        "witness"=>rel,
        "witness_sha256"=>bytes2hex(sha256(read(path))),
        "case_sha256"=>c.sha256,
        "run_id"=>w["result"]["run_id"],
        "parent_result_sha256"=>w["parent_result_sha256"],
    )
    for route in ("cuts", "critical", "paper_critical")
        push!(d["runs"], Dict("id"=>splitext(file)[1]*"--"*route, "case"=>file, "route"=>route))
    end
end
mkpath(dirname(target))
write(target, PaperRebuild.r5_market_text(d))
r5_sb_study_inputs(target)
println("Frozen eight unchanged inputs and 24 full-SOS1 strategy Benders runs before optimization.")
