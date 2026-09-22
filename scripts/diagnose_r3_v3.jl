include("r3_setup.jl")
using Clarabel
push!(LOAD_PATH, joinpath(@__DIR__, "..", "tools", "solvers"))
using Gurobi
root = isempty(ARGS) ? "results/runs/r3-v3-audit-20260917T104953" : ARGS[1]
audit = TOML.parsefile(joinpath(root, "failure.toml"))
c = load_r2_case(joinpath(root, "case.toml"))
outdir = joinpath("results", "runs", "r3-v3-equivalence-"*Dates.format(now(UTC), "yyyymmddTHHMMSS"))
mkpath(outdir)
out = Dict{String,Any}(
    "audit_source"=>root,
    "input_sha256"=>c.sha256,
    "source_hashes"=>PaperRebuild.r2_science_hashes(),
    "runs"=>Any[],
)
optimizer = r3_gurobi_factory(Gurobi)
deadline = PaperRebuild.r3_clock()+600
for role in ("minimum_cost", "minimum_violation", "first_feasible", "reference")
    selected =
        role=="reference" ? audit["reference_final"] :
        only(x["record"] for x in audit["selected"] if x["role"]==role)
    flow = selected["values"]["m_pipe"]
    operation = PaperRebuild.r3_operation_from_dict(selected["operation"])
    println("DIAGNOSE ", role)
    flush(stdout)
    for form in ("unscaled", "scaled", "physical")
        r = PaperRebuild.r3_solve(
            c,
            ()->build_r3_subproblem(
                c,
                flow;
                operation,
                physical = form=="physical",
                rescale_cones = form=="scaled",
            ),
            form=="physical" ? optimizer : Clarabel.Optimizer;
            deadline,
            budget_sec = 60,
        )
        v = validate_r3_solution(c, r)
        push!(
            out["runs"],
            Dict(
                "role"=>role,
                "form"=>form,
                "result"=>r,
                "model_pass"=>v.model_pass,
                "physical_pass"=>v.physical_pass,
                "failed_rows"=>[
                    Dict(string(k)=>getfield(x, k) for k in keys(x)) for x in v.rows if !x.pass
                ],
            ),
        )
        println(
            role,
            " ",
            form,
            " ",
            r["status"],
            " model=",
            v.model_pass,
            " physical=",
            v.physical_pass,
        )
        open(joinpath(outdir, "equivalence.toml"), "w") do io
            TOML.print(io, out; sorted = true)
        end
    end
end
println(outdir)
