using CSV, TOML
length(ARGS)==1 || error("参数：市场报告目录")
dir=only(ARGS)
rows=collect(CSV.File(joinpath(dir, "comparison.csv")))
residuals=collect(CSV.File(joinpath(dir, "residuals.csv")))
println(
    "Counts: ",
    length(rows),
    " records, ",
    count(x->x.model_pass, rows),
    " model, ",
    count(x->x.kkt_pass, rows),
    " KKT, ",
    count(x->x.independent_dual_pass, rows),
    " independent dual.",
)
println("Maximum normalized residual: ", maximum(x.normalized for x in residuals))
println(
    "Maximum effective relative gap: ",
    maximum(x.relative_gap for x in rows if x.optimality_pass),
)
println("Maximum total method seconds: ", maximum(x.total_method_elapsed_sec for x in rows))
for x in rows
    println(x.record_id, " | ", x.status, " | objective=", x.objective, " | gap=", x.relative_gap)
end
comparisons=collect(CSV.File(joinpath(dir, "solver-comparison.csv")))
println(
    "Same-model comparisons: ",
    count(x->x.A2_pass, comparisons),
    " / ",
    count(x->x.comparable, comparisons),
    " eligible; max gap=",
    maximum(x.relative_objective_difference for x in comparisons if x.comparable),
)
for x in CSV.File(joinpath(dir, "prices.csv"))
    x.solver=="highs" && println(
        x.case,
        " node=",
        x.node,
        " t=",
        x.t,
        " LMP=",
        x.LMP_USD_MWh,
        " up=",
        x.up_price_USD_MW_h,
        " down=",
        x.down_price_USD_MW_h,
    )
end
