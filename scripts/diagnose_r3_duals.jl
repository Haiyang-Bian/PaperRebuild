push!(LOAD_PATH, normpath(joinpath(@__DIR__, "..")))
include("r3_setup.jl")
using Clarabel, Gurobi

# 最小反例只记录原始求解器返回值，不改写乘子、不修改依赖库。
factory=r3_gurobi_factory(Gurobi)
records=Dict{String,Any}[]
for (solver, optimizer) in (("Clarabel", Clarabel.Optimizer), ("Gurobi", factory)),
    active in (true, false),
    scale in (1.0, 1000.0)

    model=Model(optimizer)
    set_silent(model)
    set_time_limit_sec(model, 30.0)
    if solver=="Gurobi"
        set_optimizer_attribute(model, "QCPDual", 1)
        set_optimizer_attribute(model, "BarQCPConvTol", 1e-10)
    end
    @variable(model, m)
    @variable(model, 0<=k<=10)
    fix(m, 1.0)
    cone=@constraint(model, scale*[k+1, 2m, k-1] in SecondOrderCone())
    active || fix(k, 2.0; force = true)
    @objective(model, Min, k)
    optimize!(model)
    evidence=PaperRebuild.r3_kkt(model)
    cone_dual = try
        dual(cone)
    catch err
        sprint(showerror, err)
    end
    println((;
        solver,
        active,
        scale,
        objective = objective_value(model),
        dual = cone_dual,
        reason = evidence["reason"],
        trusted = evidence["trusted"],
    ))
    push!(
        records,
        Dict(
            "solver"=>solver,
            "active"=>active,
            "scale"=>scale,
            "cone_dual"=>cone_dual,
            "objective"=>objective_value(model),
            "kkt"=>evidence,
            "termination"=>string(termination_status(model)),
            "dual_status"=>string(dual_status(model)),
        ),
    )
end
path=joinpath(
    "results",
    "runs",
    "r3-dual-diagnostic-"*Dates.format(now(UTC), "yyyymmddTHHMMSS")*".toml",
)
open(io->TOML.print(io, Dict("records"=>records); sorted = true), path, "w")
println(path)
