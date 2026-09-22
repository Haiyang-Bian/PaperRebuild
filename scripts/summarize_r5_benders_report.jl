using CSV, TOML
length(ARGS)==1||error(
    "参数：已有分解报告目录；这里只汇总CSV，独立重读使用check_r5_benders_artifacts.jl",
)
dir=abspath(only(ARGS));
rows=collect(CSV.File(joinpath(dir, "comparison.csv")))
println("Stored CSV statistics, not an independent replay:")
for solver in sort!(unique(x.solver for x in rows)), route in ("cuts", "critical", "paper_critical")
    group=filter(x->x.solver==solver&&x.route==route, rows)
    isempty(group)&&continue
    println(
        solver,
        " / ",
        route,
        " | runs=",
        length(group),
        " model=",
        count(x->x.model_pass, group),
        " full=",
        count(x->x.cost_complete, group),
        " restricted=",
        count(x->x.restricted_stopping, group),
        " A2=",
        count(x->x.A2_pass, group),
        " max seconds=",
        maximum(x.elapsed_sec for x in group),
    )
end
certified=filter(x->x.same_domain_certified_pair, rows)
println(
    "Max certified relative difference: ",
    maximum(x.candidate_relative_difference for x in certified),
)
println("Max certified own relative gap: ", maximum(x.full_relative_gap for x in certified))
println("Max budget overrun seconds: ", maximum(x.budget_overrun_sec for x in rows))
res=collect(CSV.File(joinpath(dir, "selected-residuals.csv")))
println(
    "Selected residuals: ",
    length(res),
    "; failures=",
    count(x->!x.pass, res),
    "; max ratio=",
    maximum(x.normalized for x in res),
)
allrows=collect(CSV.File(joinpath(dir, "residuals.csv")))
println(
    "All scalar residuals aggregated: ",
    sum(x.count for x in allrows),
    "; failures=",
    sum(x.failures for x in allrows),
)
for x in filter(
    x->x.route=="paper_critical"&&x.candidate_comparable&&abs(x.candidate_cost_difference)>1e-4,
    rows,
)
    println("Restricted cost excess ", x.case, ": ", x.candidate_cost_difference)
end
sizes=[
    (filesize(joinpath(base, file)), replace(relpath(joinpath(base, file), dir), '\\'=>'/')) for
    (base, _, files) in walkdir(dir) for file in files
]
sort!(sizes; by = x->-x[1])
println("Largest public file: ", first(sizes))
for name in ("future_e030_r005", "thermal_e100_r000"), route in ("critical", "paper_critical")
    w=TOML.parsefile(joinpath(dir, "witnesses", name*"--"*route*"--highs", "witness.toml"))
    r=w["result"]
    step=r["iterations"][r["selected_iteration"]]
    println(
        "Selected policy ",
        name,
        " / ",
        route,
        " | z=",
        step["candidate"]["z"],
        " | critical=",
        step["master"]["critical"],
        " | scenarios=",
        [s["id"] for s in w["case"]["commitment"]["scenarios"]],
    )
end
