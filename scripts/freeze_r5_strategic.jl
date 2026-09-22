using PaperRebuild, TOML, SHA
include("r5_strategic_cases.jl")
root=normpath(joinpath(@__DIR__, ".."))
output=joinpath(root, "configs", "r5", "strategic")
ispath(output)&&error("策略输入已存在，不覆盖冻结数据")
mkpath(output)
cases=[
    r5_strategic_fixture(s) for
    s in ("hard_zero", "quarter", "thermal_e030_r005", "future_e030_r005", "physical_infeasible")
]
append!(
    cases,
    [
        r5_strategic_merit_fixture(),
        r5_strategic_merit_fixture(; fixed_bid = true),
        r5_strategic_scarcity_fixture(),
    ],
)
files=Dict{String,String}()
rules=Dict{String,Any}(
    "schema"=>"r5-strategic-study-v1",
    "origin"=>"synthetic",
    "budget_sec"=>600.0,
    "selection"=>"optimistic_primal_dual",
    "solver_seed"=>23,
    "gurobi_PreSOS1BigM"=>0,
    "gurobi_DualReductions"=>0,
    "price_caps_imposed"=>false,
    "reference_injected"=>false,
    "runs"=>Dict{String,Any}[],
    "files"=>files,
    "scope"=>"Synthetic continuous bid/risk connection; fixed-complementarity bounds are branch-only; no out-of-sample or thesis-scale claim.",
    "construction_sha256"=>bytes2hex(sha256(read(@__FILE__))),
    "fixture_sha256"=>bytes2hex(sha256(read(joinpath(@__DIR__, "r5_strategic_cases.jl")))),
)
for c in cases
    filename=c.data["name"]*".toml"
    text=PaperRebuild.r5_market_text(c.data)
    write(joinpath(output, filename), text)
    files[filename]=bytes2hex(sha256(text))
    push!(
        rules["runs"],
        Dict(
            "id"=>c.data["name"]*"-sos1",
            "case"=>filename,
            "solver"=>"gurobi",
            "method"=>"sos1",
            "budget_sec"=>600.0,
        ),
    )
    if !(c.data["name"] in ("competitive_physical_infeasible", "scarcity_unbounded_price"))
        pattern=Dict(k=>0 for k in keys(build_r5_strategic(c).market.pairs))
        if startswith(c.data["name"], "merit")
            for k in keys(pattern)
                occursin("lower/R_", k)&&(pattern[k]=1)
            end
            pattern["g_cap_up/1/1"]=1
            pattern["lower/P_G/2/1"]=c.data["name"]=="merit_fixed_bid" ? 0 : 1
        end
        push!(
            rules["runs"],
            Dict(
                "id"=>c.data["name"]*"-branch",
                "case"=>filename,
                "solver"=>"highs",
                "method"=>"fixed_complementarity",
                "budget_sec"=>600.0,
                "complementarity_pattern"=>pattern,
            ),
        )
    end
end
rules["analytic_expectations"]=Dict(
    "competitive_hard_zero"=>2.085,
    "competitive_quarter"=>0.52125,
    "merit_strategic"=>7.46,
    "merit_fixed_bid"=>14.2,
)
rules["selection_cases"]=[
    Dict(
        "id"=>name,
        "case"=>"configs/r5/market/"*name*".toml",
        "sha256"=>bytes2hex(sha256(read(joinpath(root, "configs", "r5", "market", name*".toml")))),
    ) for name in ("hand_hour", "wide_line")
]
write(joinpath(output, "study.toml"), PaperRebuild.r5_market_text(rules))
println(
    "Frozen ",
    length(cases),
    " inputs / ",
    length(rules["runs"]),
    " strategy methods / 2 fixed-award settlement audits; no optimization.",
)
