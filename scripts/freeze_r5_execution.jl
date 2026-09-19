using PaperRebuild, TOML, SHA
root=normpath(joinpath(@__DIR__, ".."))
path=joinpath(root, "configs", "r5", "execution", "study.toml")
ispath(path) && error("不得覆盖执行规则冻结")
positive=[
    "competitive_hard_zero",
    "competitive_quarter",
    "competitive_thermal_e030_r005",
    "competitive_future_e030_r005",
    "merit_strategic",
    "merit_fixed_bid",
]
negative=["competitive_physical_infeasible", "scarcity_unbounded_price"]
runs=Dict{String,Any}[]
for name in vcat(positive, negative)
    parent="results/summaries/r5-strategic/witnesses/$name-sos1.toml"
    w=TOML.parsefile(joinpath(root, split(parent, '/')...))
    c=R5StrategicCase(w["case"])
    variants=name in positive ? ["saved_selected", "saved_independent", "minimum_norm"] :
             ["preset_minimum_norm"]
    for variant in variants
        push!(
            runs,
            Dict(
                "id"=>"$name-$variant",
                "case"=>name,
                "mode"=>variant,
                "parent"=>parent,
                "parent_sha256"=>bytes2hex(sha256(read(joinpath(root, split(parent, '/')...)))),
                "case_sha256"=>c.sha256,
            ),
        )
    end
end
for name in ("hand_hour", "wide_line")
    rel="configs/r5/market/$name.toml"
    push!(
        runs,
        Dict(
            "id"=>"market-$name-minimum_norm",
            "case"=>name,
            "mode"=>"market_only",
            "input"=>rel,
            "input_sha256"=>bytes2hex(sha256(read(joinpath(root, split(rel, '/')...)))),
        ),
    )
end
rules=Dict{String,Any}(
    "schema"=>"r5-execution-study-rules-v1",
    "origin"=>"synthetic",
    "version"=>"r5_execution_min_norm_v1",
    "budget_sec"=>600.0,
    "selection_budget_sec"=>180.0,
    "spec"=>PaperRebuild.r5_execution_spec(R5MarketExecutionSpec()),
    "parent_archive_commit"=>"db56b3f",
    "parent_science_commit"=>"e86b6d9",
    "lp_solver"=>"highs",
    "qp_solver"=>"clarabel",
    "recourse_solver"=>"highs",
    "preset_bid_rule"=>"midpoint_of_declared_bid_bounds_for_two_no_candidate_parents",
    "meaning"=>"Fixed previously chosen bids evaluated under explicit execution; no strategic reoptimization.",
    "fixture_sha256"=>bytes2hex(sha256(read(@__FILE__))),
    "runs"=>runs,
)
mkpath(dirname(path))
write(path, PaperRebuild.r5_market_text(rules))
println("Frozen 22 execution/delivery records; no solver called.")
