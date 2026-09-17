include("r3_setup.jl")
using Clarabel

function r4_gurobi()
    env=Gurobi.Env(Dict{String,Any}("OutputFlag"=>0))
    return optimizer_with_attributes(
        ()->Gurobi.Optimizer(env),
        "Threads"=>1,
        "Seed"=>23,
        "FeasibilityTol"=>1e-9,
        "OptimalityTol"=>1e-9,
        "MIPGap"=>1e-6,
        "NonConvex"=>2,
    )
end

function r4_optimizer(which)
    if which==:gurobi
        root=normpath(joinpath(@__DIR__, ".."))
        push!(LOAD_PATH, joinpath(root, "tools", "solvers"))
        @eval using Gurobi
        return Base.invokelatest(r4_gurobi)
    elseif which==:clarabel
        return optimizer_with_attributes(
            Clarabel.Optimizer,
            "tol_feas"=>1e-9,
            "tol_gap_abs"=>1e-9,
            "tol_gap_rel"=>1e-9,
        )
    end
    error("未知求解器")
end
