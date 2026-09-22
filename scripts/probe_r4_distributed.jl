# 开发运行单独封存，不进入正式证据；输入与模式不得由结果反向选择。
include("r4_setup.jl")
using Dates
c=load_r4_case(joinpath(@__DIR__, "..", "configs", "r4", "baseline", "open_flexible.toml"))
purpose=isempty(ARGS) ? :swm : Symbol(only(ARGS))
r=solve_r4_distributed(
    c;
    optimizer = r4_optimizer(:clarabel),
    modes = [1, 0, 1, 0],
    purpose,
    budget_sec = 60,
)
println(r["status"], " ", r["validation"])
haskey(r, "error") && println(r["error"])
path=save_r4_distributed_run(
    c,
    r;
    run_id = "development-distributed-"*string(purpose)*"-"*Dates.format(now(), "yyyymmddTHHMMSS"),
)
read_r4_distributed_run(path)
println(path)
