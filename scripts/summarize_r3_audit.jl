include("r3_setup.jl")
using CSV, Clarabel
root="results/runs/r3-v3-audit-20260917T104953"
a=TOML.parsefile(joinpath(root, "failure.toml"));
c=load_r2_case(joinpath(root, "case.toml"))
eq=TOML.parsefile("results/runs/r3-v3-equivalence-20260917T105739/equivalence.toml")
for x in a["selected"]
    r=x["record"]
    println(
        x["role"],
        " #",
        x["stage_index"],
        " ",
        r["status"],
        " cost=",
        get(r, "operating_cost", NaN),
    )
end
out=Dict{String,Any}("input_sha256"=>c.sha256, "witnesses"=>Any[])
for x in eq["runs"]
    x["form"]=="unscaled" || continue
    r=x["result"]
    op=PaperRebuild.r3_operation_from_dict(r["operation"])
    b=build_r3_subproblem(c, r["flow_schedule"]; operation = op, rescale_cones = true)
    # 相同变量顺序的原始数值见证，在等价模型中逐项复核。
    u=build_r3_subproblem(c, r["flow_schedule"]; operation = op)
    set_optimizer(u.model, Clarabel.Optimizer)
    set_silent(u.model)
    for key in ("tol_gap_abs", "tol_gap_rel", "tol_feas")
        set_optimizer_attribute(u.model, key, 1e-9)
    end
    optimize!(u.model)
    vars=all_variables(u.model)
    vals=value.(vars)
    report=primal_feasibility_report(b.model, Dict(zip(all_variables(b.model), vals)); atol = 1e-6)
    println(
        x["role"],
        " scaled witness violations=",
        length(report),
        " grid range=",
        extrema(r["values"]["P_grid"]),
    )
    push!(
        out["witnesses"],
        Dict(
            "role"=>x["role"],
            "flow"=>r["flow_schedule"],
            "operation"=>r["operation"],
            "values"=>vals,
            "violations"=>[Dict("constraint"=>string(k), "residual"=>v) for (k, v) in report],
        ),
    )
end
target=joinpath("results", "runs", "r3-v3-witness-"*Dates.format(now(UTC), "yyyymmddTHHMMSS"))
mkpath(target)
open(joinpath(target, "witness.toml"), "w") do io
    TOML.print(io, out; sorted = true)
end
println(target)
