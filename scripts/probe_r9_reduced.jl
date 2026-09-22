push!(LOAD_PATH, normpath(joinpath(@__DIR__, "..")))
using PaperRebuild, JuMP, TOML, SHA
length(ARGS) in (4, 5, 6) || error(
    "usage: probe_r9_reduced.jl CASE CF_CT|CF_VT Clarabel|Gurobi NEW_OUTPUT [physical] [anchored]",
)
casepath, mode, solver, output = ARGS[1], Symbol(ARGS[2]), ARGS[3], ARGS[4]
options = ARGS[5:end]
all(x -> x in ("physical", "anchored"), options) || error("未知选项")
physical = "physical" in options
terminal = "anchored" in options ? :reference_anchored : :literal
ispath(output) && error("不覆盖已有开发证据")
solver in ("Clarabel", "Gurobi") || error("未知求解器")
if solver == "Clarabel"
    @eval using Clarabel
else
    @eval using Gurobi
end
optimizer = getproperty(getfield(Main, Symbol(solver)), :Optimizer)
c = load_r9_pv_case(casepath)
mkpath(output)
cp(casepath, joinpath(output, "case.toml"))
# 原始状态和当前实现一起保存，开发失败同样保留；不替代正式冻结批次。
root = normpath(joinpath(@__DIR__, ".."))
paths = [
    "src/formulations/r9_reduced.jl",
    "src/reporting/r9_reduced.jl",
    "src/verification/r9_reduced.jl",
    "scripts/probe_r9_reduced.jl",
]
hashes = Dict(p => bytes2hex(sha256(read(joinpath(root, p)))) for p in paths)
for p in paths
    target = joinpath(output, "code", p)
    mkpath(dirname(target))
    cp(joinpath(root, p), target)
end
open(
    io -> TOML.print(
        io,
        Dict(
            "schema" => "r9-reduced-development-v1",
            "input_sha256" => c.sha256,
            "mode" => string(mode),
            "solver" => solver,
            "physical" => physical,
            "terminal_interpretation" => string(terminal),
            "budget_sec" => 60.0,
            "source_hashes" => hashes,
        );
        sorted = true,
    ),
    joinpath(output, "manifest.toml"),
    "w",
)
r = Base.invokelatest(
    () -> solve_r9_reduced_case(c; mode, physical, optimizer, terminal, budget_sec = 60.0),
)
all(hashes[p] == bytes2hex(sha256(read(joinpath(root, p)))) for p in paths) ||
    error("运行中源码改变")
open(io -> TOML.print(io, r; sorted = true), joinpath(output, "result.toml"), "w")
println("certificate=", r["representation_certificate"])
println("status=", r["status"], " cost=", get(r["stage"], "operating_cost", "missing"))
println(
    "termination=",
    get(r["stage"], "termination", "missing"),
    " primal=",
    get(r["stage"], "primal", "missing"),
    " elapsed_sec=",
    r["elapsed_sec"],
)
if haskey(r, "diagnostic_candidate")
    near = r["diagnostic_candidate"]
    println(
        "unaccepted_candidate_cost=",
        near["stage"]["operating_cost"],
        " validation=",
        near["validation"],
        " daily_heat=",
        near["daily_heat"],
    )
end
if haskey(r["stage"], "values")
    v = validate_r9_reduced_solution(c, r)
    println("model=", v.model_pass, " physics=", v.physical_pass)
    println("daily heat=", r["daily_heat"])
    for row in v.rows
        row.pass || println(row)
    end
end
