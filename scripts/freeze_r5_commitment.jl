using PaperRebuild, TOML, SHA
include("r5_commitment_cases.jl")
length(ARGS)==1||error("参数：新的冻结输入目录")
dir=abspath(only(ARGS))
ispath(dir)&&error("不覆盖已有共同承诺输入")
cases=Dict(k=>R5CommitmentCase(v) for (k, v) in r5_commitment_inputs())
mkpath(dir)
hashes=Dict{String,String}()
for name in sort!(collect(keys(cases)))
    file=name*".toml"
    write(joinpath(dir, file), PaperRebuild.r5_market_text(cases[name].data))
    hashes[file]=bytes2hex(sha256(read(joinpath(dir, file))))
end
runs=[
    Dict("id"=>name*"--"*solver, "case"=>name*".toml", "solver"=>solver) for
    name in sort!(collect(keys(cases))) for solver in ("highs", "clarabel")
]
append!(
    runs,
    [
        Dict("id"=>name*"--gurobi", "case"=>name*".toml", "solver"=>"gurobi") for
        name in ("hand", "four_period")
    ],
)
study=Dict(
    "schema"=>"r5-commitment-study-v1",
    "origin"=>"synthetic",
    "budget_sec"=>60.0,
    "source_rule"=>"Derived analytically before optimization; shared full-trajectory recourse, not risk or bidding.",
    "analytic"=>Dict(
        "hand_first_stage"=>[0.08, 0.08, 0.062],
        "hand_cost"=>2.085,
        "quarter_cost"=>0.52125,
        "no_reserve_cost"=>14.2,
        "no_call_only_cost"=>-1.8,
        "overcommitted"=>"down activation requires 0.16 MW import but demand is 0.142 MW and export is forbidden",
    ),
    "files"=>hashes,
    "runs"=>runs,
)
write(joinpath(dir, "study.toml"), PaperRebuild.r5_market_text(study))
println(
    "Frozen ",
    length(cases),
    " shared-commitment inputs and ",
    length(runs),
    " run rules; no optimization.",
)
