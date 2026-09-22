include("r5_market_setup.jl")
function r5_risk_optimizer(which)
    factory=r5_market_optimizer(which)
    if which==:highs
        push!(factory.params, MOI.RawOptimizerAttribute("mip_rel_gap")=>1e-9)
        push!(factory.params, MOI.RawOptimizerAttribute("mip_feasibility_tolerance")=>1e-9)
    elseif which==:gurobi
        push!(factory.params, MOI.RawOptimizerAttribute("MIPGap")=>1e-9)
        push!(factory.params, MOI.RawOptimizerAttribute("IntFeasTol")=>1e-9)
    end
    factory
end
