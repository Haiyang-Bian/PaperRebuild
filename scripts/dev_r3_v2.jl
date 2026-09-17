include("r3_setup.jl")
using Clarabel
c=load_r2_case("configs/r2/single-source.toml")
m=PaperRebuild.r2_flow_matrix(c)
r=solve_r3_projected_gradient(
    c;
    algorithm = :r3_pg_checked_v2,
    initial_flow = m,
    convex_optimizer = Clarabel.Optimizer,
    budget_sec = 120,
    max_iterations = 200,
)
@show r["outer_status"] length(r["iterations"]) r["final_stage"]
all(validate_r3_iteration(c, row; stages = r["stages"]).pass for row in r["iterations"]) ||
    error("迭代证据不一致")
println(
    "accepted local steps=",
    sum(
        count(t->t["kind"]=="primal_local_model" && t["accepted"], row["trials"]) for
        row in r["iterations"]
    ),
)
@show validate_r3_solution(c, r).physical_pass
path=save_r3_run(c, r; run_id = "r3-v2-development-"*Dates.format(now(UTC), "yyyymmddTHHMMSS"))
@show read_r3_run(path).validation.physical_pass
