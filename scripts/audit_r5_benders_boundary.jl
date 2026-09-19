using PaperRebuild, JuMP, HiGHS, Clarabel, TOML, Dates, UUIDs
include("r5_risk_setup.jl")
root=normpath(joinpath(@__DIR__, ".."))
length(ARGS)<=3||error("参数：新审计目录 [float_box|rational_box] [diagnostic_scale]")
target=isempty(ARGS) ? joinpath(root, "tmp", "r5-benders-boundary-"*string(uuid4())) :
       abspath(ARGS[1])
arithmetic=length(ARGS)>=2 ? Symbol(ARGS[2]) : :float_box
scale=length(ARGS)>=3 ? parse(Float64, ARGS[3]) : 1.0
ispath(target)&&error("不覆盖边界审计")
c=load_r5_risk_case(joinpath(root, "configs", "r5", "risk", "hard_zero.toml"))
r=solve_r5_benders(
    c;
    optimizer = r5_risk_optimizer(:highs),
    oracle_optimizer = r5_risk_optimizer(:clarabel),
    spec = R5BendersSpec(cut_arithmetic = arithmetic, diagnostic_scale = scale),
    budget_sec = 60,
)
save_r5_benders_run(c, r, target)
println("Development audit ", r["status"], " saved ", target)
for step in r["iterations"]
    m=step["master"]
    println(
        "iteration ",
        step["iteration"],
        " x=",
        get(m, "first_stage", Dict()),
        " gap=",
        get(step, "gap", Dict()),
    )
    for (sid, id) in step["diagnostic_source_ids"]
        src=r["subproblems"][id]
        cut=r5_benders_cut(c, src; arithmetic)
        println(
            sid,
            " phase=",
            src["solver_objective"],
            " source=",
            cut["source_value"],
            " rounding=",
            cut["rounding_guard"],
            " stationary=",
            cut["stationarity_guard"],
            " sign=",
            cut["sign_guard"],
        )
    end
end
