include("r4_setup.jl")
root=normpath(joinpath(@__DIR__, ".."))
name=length(ARGS)>=1 ? ARGS[1] : "base"
variant=length(ARGS)>=2 ? ARGS[2] : "central_socp"
solver=length(ARGS)>=3 ? Symbol(ARGS[3]) : :gurobi
variant in ("central_socp", "central_exact", "independent_exact") || error("未知运行配置")
c=load_r4_case(joinpath(root, "configs", "r4", name*".toml"))
spec=R4Spec(
    operation = startswith(variant, "independent") ? :independent : :central,
    electric = endswith(variant, "exact") ? :exact : :socp,
)
r=solve_r4_case(c; spec, optimizer = r4_optimizer(solver), enumerate_battery = solver==:clarabel)
dir=save_r4_run(c, r; directory = joinpath(root, "results", "runs", "r4"))
println(dir)
println((
    status = r["status"],
    model = r["validation"]["model_pass"],
    electric = r["validation"]["electric_original_pass"],
))
