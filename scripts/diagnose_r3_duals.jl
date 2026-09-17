push!(LOAD_PATH, normpath(joinpath(@__DIR__, "..")))
include("r3_setup.jl")
using Clarabel, Gurobi

# 最小反例只记录原始求解器返回值，不改写乘子、不修改依赖库。
factory=r3_gurobi_factory(Gurobi)
records=Dict{String,Any}[]
function native_duals(model)
    backend=unsafe_backend(model)
    out=Dict{String,Any}()
    for (countname, attribute) in (("NumConstrs", "Pi"), ("NumQConstrs", "QCPi"), ("NumVars", "RC"))
        n=Ref{Cint}(0)
        code=Gurobi.GRBgetintattr(backend, countname, n)
        code==0 || (out[attribute] = Dict("error_code"=>code); continue)
        values=zeros(Float64, n[])
        code=Gurobi.GRBgetdblattrarray(backend, attribute, 0, n[], values)
        out[attribute]=code==0 ? Dict("values"=>values) : Dict("error_code"=>code)
    end
    return out
end
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
    solver=="Gurobi" && (last(records)["native_duals"]=native_duals(model))
end
path=joinpath(
    "results",
    "runs",
    "r3-dual-diagnostic-"*Dates.format(now(UTC), "yyyymmddTHHMMSS")*".toml",
)
open(io->TOML.print(io, Dict("records"=>records); sorted = true), path, "w")
println(path)
