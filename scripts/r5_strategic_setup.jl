include("r5_risk_setup.jl")
function r5_strategic_optimizer(which)
    f = r5_risk_optimizer(which)
    if which == :gurobi
        # SOS1原生分支，不让预处理引入任意乘子上界；状态消歧只适用于本次显式新规则。
        push!(f.params, MOI.RawOptimizerAttribute("PreSOS1BigM")=>0)
        push!(f.params, MOI.RawOptimizerAttribute("DualReductions")=>0)
    end
    f
end
