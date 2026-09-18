# 保存开发阶段的失败及逐约束证据；不改输入，不调整验收门槛。
include("r4_setup.jl")
c=load_r4_case(joinpath(@__DIR__, "..", "configs", "r4", "baseline", "import_flexible.toml"))
which=isempty(ARGS) ? :clarabel : Symbol(only(ARGS))
r=solve_r4_case(
    c;
    spec = R4Spec(operation = :independent),
    optimizer = r4_optimizer(which),
    enumerate_battery = which==:clarabel,
    budget_sec = 60,
)
path=save_r4_run(c, r; directory = joinpath("results", "runs", "r4-baseline-development"))
println(path)
println("Overall: ", r["status"])
for local_run in r["local_stages"]
    println("Actor ", local_run["actor"], ": ", local_run["status"])
    for row in local_run["validation"]["rows"]
        row["pass"] || println(row)
    end
    for log in local_run["solves"]
        haskey(log, "error_summary") && println(log["error_summary"])
    end
end
