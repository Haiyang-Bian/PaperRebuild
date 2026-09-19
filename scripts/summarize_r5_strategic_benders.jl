using CSV, TOML
length(ARGS) == 1 || error("参数：策略分解报告目录")
dir = abspath(only(ARGS))
meta = TOML.parsefile(joinpath(dir, "report.toml"))
println(
    "records/model/full/restricted/A2/residuals/max = ",
    [
        meta[k] for k in (
            "records",
            "model_pass",
            "cost_complete",
            "restricted_stopping",
            "A2_pass",
            "selected_residual_count",
            "max_selected_normalized_residual",
        )
    ],
)
rows = collect(CSV.File(joinpath(dir, "comparison.csv")))
for r in rows
    println(
        r.record_id,
        " | ",
        r.status,
        " | cost=",
        r.upper_bound,
        " | diff=",
        r.candidate_cost_difference,
        " | iterations=",
        r.iterations,
        " | seconds=",
        r.elapsed_sec,
        " | A2=",
        r.A2_pass,
    )
end
println(
    "maximum finite relative difference = ",
    maximum((r.candidate_relative_difference for r in rows if r.A2_pass); init = 0.0),
)
println("maximum budget overrun = ", maximum(r.budget_overrun_sec for r in rows))
