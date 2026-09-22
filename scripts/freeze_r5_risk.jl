include("r5_risk_cases.jl")
root=normpath(joinpath(@__DIR__, ".."))
dest=joinpath(root, "configs", "r5", "risk")
ispath(dest)&&error("不覆盖冻结风险输入")
cases=r5_risk_inputs()
validated=Dict(k=>R5RiskCase(v) for (k, v) in cases)
mkpath(dest)
hashes=Dict{String,String}()
for name in sort!(collect(keys(validated)))
    path=joinpath(dest, name*".toml")
    write(path, PaperRebuild.r5_market_text(validated[name].data))
    hashes[name*".toml"]=bytes2hex(sha256(read(path)))
end
rules=Dict{String,Any}(
    "schema"=>"r5-risk-study-rules-v1",
    "origin"=>"synthetic",
    "budget_sec"=>60.0,
    "frozen_before_optimization"=>true,
    "files"=>hashes,
    "scope"=>"Fixed-price finite-support DRO and joint indoor-temperature chance constraints; not strategic bidding, online control, continuous support or out-of-sample reliability.",
    "runs"=>Dict{String,Any}[],
)
for name in sort!(collect(keys(validated))),
    (solver, method) in (("highs", "direct"), ("clarabel", "enumeration"))

    push!(
        rules["runs"],
        Dict("id"=>name*"--"*solver, "case"=>name*".toml", "solver"=>solver, "method"=>method),
    )
end
for name in ("hard_zero", "thermal_e030_r005", "future_e030_r005")
    push!(
        rules["runs"],
        Dict("id"=>name*"--gurobi", "case"=>name*".toml", "solver"=>"gurobi", "method"=>"direct"),
    )
end
write(joinpath(dest, "study.toml"), PaperRebuild.r5_market_text(rules))
println(
    "Frozen ",
    length(validated),
    " risk inputs and ",
    length(rules["runs"]),
    " method rules; no optimization performed.",
)
