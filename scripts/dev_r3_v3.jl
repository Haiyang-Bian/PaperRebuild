include("r3_setup.jl")
using Clarabel
push!(LOAD_PATH, joinpath(@__DIR__, "..", "tools", "solvers"))
using Gurobi
const PR=PaperRebuild
c=load_r2_case("results/summaries/r3-v3/audit/case.toml")
a=TOML.parsefile("results/summaries/r3-v3/audit/failure.toml")
center=only(x["record"] for x in a["selected"] if x["role"]=="minimum_violation")
center=PR.reconstruct_r3_pressure(c, center);
center["v3_physical_review"]=true
o=PR.r3_operation_from_dict(center["operation"])
recovery=PR.r3_restore_physical(
    c,
    center,
    Clarabel.Optimizer;
    operation = o,
    deadline = PR.r3_clock()+120,
)
println(
    "RECOVERY ",
    recovery.status,
    " attempts=",
    length(recovery.trace),
    " physical=",
    validate_r3_solution(c, recovery.candidate).physical_pass,
)
for row in recovery.trace
    println(
        row["update"],
        "/",
        row["attempt"],
        " ",
        get(row, "reason", "candidate"),
        " accepted=",
        row["accepted"],
        " before=",
        row["before"],
        " after=",
        get(row, "after", NaN),
    )
end
target="results/runs/r3-v3-dev-"*Dates.format(now(UTC), "yyyymmddTHHMMSS")
mkpath(target)
open(
    io->TOML.print(
        io,
        Dict("trace"=>recovery.trace, "candidate"=>recovery.candidate, "status"=>recovery.status);
        sorted = true,
    ),
    joinpath(target, "recovery.toml"),
    "w",
)
if validate_r3_solution(c, recovery.candidate).physical_pass
    r=PR.r3_solve(
        c,
        ()->build_r3_subproblem(
            c,
            recovery.candidate["values"]["m_pipe"];
            physical = true,
            operation = o,
        ),
        r3_gurobi_factory(Gurobi);
        budget_sec = 60,
    )
    println("FINAL ", r["status"], " ", validate_r3_solution(c, r).physical_pass)
    open(io->TOML.print(io, r; sorted = true), joinpath(target, "physical.toml"), "w")
end
println(target)
