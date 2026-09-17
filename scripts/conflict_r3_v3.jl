include("r3_setup.jl")
push!(LOAD_PATH, joinpath(@__DIR__, "..", "tools", "solvers"))
using Gurobi
c=load_r2_case("results/summaries/r3-v3/audit/case.toml")
a=TOML.parsefile("results/summaries/r3-v3/audit/failure.toml")
s=only(x["record"] for x in a["selected"] if x["role"]=="minimum_cost")
o=PaperRebuild.r3_operation_from_dict(s["operation"])
b=build_r3_subproblem(
    c,
    s["values"]["m_pipe"];
    physical = true,
    operation = o,
    optimizer = r3_gurobi_factory(Gurobi),
)
set_silent(b.model)
for (key, value) in (
    "NonConvex"=>2,
    "Threads"=>1,
    "Seed"=>0,
    "FeasibilityTol"=>1e-9,
    "OptimalityTol"=>1e-9,
    "TimeLimit"=>60.0,
)
    set_optimizer_attribute(b.model, key, value)
end
optimize!(b.model)
out=Dict{String,Any}(
    "input_sha256"=>c.sha256,
    "flow_sha256"=>s["flow_sha256"],
    "termination"=>string(termination_status(b.model)),
    "constraints"=>Any[],
)
if termination_status(b.model)==MOI.INFEASIBLE
    try
        compute_conflict!(b.model)
        out["conflict_status"]=string(MOI.get(backend(b.model), MOI.ConflictStatus()))
        labels=Dict(cr=>id for (id, rows) in b.constraints for cr in rows)
        out["unavailable_constraint_types"]=String[]
        for (F, S) in list_of_constraint_types(b.model), cr in all_constraints(b.model, F, S)
            status=try
                MOI.get(b.model, MOI.ConstraintConflictStatus(), cr)
            catch err
                if err isa Union{MOI.GetAttributeNotAllowed,MOI.UnsupportedAttribute}
                    label=string(F, " in ", S)
                    label in out["unavailable_constraint_types"] ||
                        push!(out["unavailable_constraint_types"], label)
                    continue
                end
                rethrow()
            end
            status==MOI.IN_CONFLICT || continue
            push!(
                out["constraints"],
                Dict(
                    "equation"=>get(labels, cr, "variable_bound_or_fix"),
                    "expression"=>string(cr),
                    "status"=>string(status),
                ),
            )
        end
    catch err
        out["conflict_error"]=sprint(showerror, err)
    end
end
folder="results/runs/r3-v3-conflict-"*Dates.format(now(UTC), "yyyymmddTHHMMSS")
mkpath(folder)
open(io->TOML.print(io, out; sorted = true), joinpath(folder, "conflict.toml"), "w")
println(
    "conflict=",
    get(out, "conflict_status", get(out, "conflict_error", "unavailable")),
    " constraints=",
    length(out["constraints"]),
    " ",
    folder,
)
