include("r5_benders_study_rules.jl")
using Dates
root=normpath(joinpath(@__DIR__, ".."))
target=joinpath(root, "configs", "r5", "benders", "study.toml")
ispath(target)&&error("不覆盖分解冻结规则")
old=TOML.parsefile(joinpath(root, "configs", "r5", "risk", "study.toml"))
rules=Dict{String,Any}(
    "schema"=>"r5-benders-study-rules-v1",
    "origin"=>"synthetic",
    "frozen_before_optimization"=>true,
    "frozen_utc"=>string(now(UTC)),
    "science_commit"=>readchomp(`git -C $root rev-parse HEAD`),
    "science_sha256"=>PaperRebuild.r5_benders_science_hashes(),
    "budget_sec"=>600.0,
    "oracle_solver"=>"clarabel",
    "scope"=>"Fixed-price finite-support risk dispatch. 39 three-route runs plus three predeclared Gurobi critical-route checks. Restricted bounds are not full-domain bounds; no scale or speed claim.",
    "initialization"=>"Empty cuts and critical set; no reference policy injection.",
    "files"=>old["files"],
    "spec"=>Dict(
        "critical_count"=>1,
        "max_iterations"=>200,
        "absolute_gap"=>1e-7,
        "relative_gap"=>1e-6,
        "cut_arithmetic"=>"rational_box",
        "diagnostic_scale"=>1024.0,
    ),
    "references"=>Dict{String,Any}(),
    "runs"=>Dict{String,Any}[],
)
for file in sort!(collect(keys(old["files"])))
    path=joinpath(root, "configs", "r5", "risk", file)
    bytes2hex(sha256(read(path)))==old["files"][file]||error("原输入变化")
    c=load_r5_risk_case(path)
    stem=splitext(file)[1]
    rel="results/summaries/r5-risk/witnesses/$stem--highs.toml"
    w=TOML.parsefile(joinpath(root, split(rel, '/')...))
    R5RiskCase(w["case"]).sha256==c.sha256||error("参考输入不同")
    rules["references"][file]=Dict(
        "witness"=>rel,
        "witness_sha256"=>bytes2hex(sha256(read(joinpath(root, split(rel, '/')...)))),
        "case_sha256"=>c.sha256,
        "run_id"=>w["result"]["run_id"],
        "parent_result_sha256"=>w["parent_result_sha256"],
    )
    for route in ("cuts", "critical", "paper_critical")
        push!(
            rules["runs"],
            Dict("id"=>"$stem--$route--highs", "case"=>file, "route"=>route, "solver"=>"highs"),
        )
    end
end
for file in ("hard_zero.toml", "thermal_e030_r005.toml", "future_e030_r005.toml")
    push!(
        rules["runs"],
        Dict(
            "id"=>splitext(file)[1]*"--critical--gurobi",
            "case"=>file,
            "route"=>"critical",
            "solver"=>"gurobi",
        ),
    )
end
mkpath(dirname(target))
write(target, PaperRebuild.r5_market_text(rules))
r5_benders_study_inputs(target)
println("Frozen 13 inputs, 39 route comparisons and 3 Gurobi checks before formal optimization.")
