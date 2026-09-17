using PaperRebuild, TOML, Dates, CSV

length(ARGS)>=2 || error("usage: r3_task.jl validate|stages|plot RUN_DIR [NEW_FIGURE_DIR]")
action, directory = ARGS[1:2]
loaded=read_r3_run(directory)
println("Run: ", loaded.metadata["run_id"], " | ", loaded.result["status"])
if action=="validate"
    println("Independent physical acceptance: ", loaded.validation.physical_pass)
    for (i, s) in enumerate(loaded.result["stages"])
        r=loaded.validation.stages[i]
        println(
            i,
            " ",
            s["stage"],
            ": ",
            s["status"],
            " model=",
            r.model_pass,
            " physical=",
            r.physical_pass,
        )
    end
    loaded.validation.physical_pass || exit(2)
elseif action=="stages"
    if !isfile(joinpath(directory, "stages.csv"))
        println("No stages were executed; inspect initialization status in run.toml.")
        exit(0)
    end
    for row in CSV.File(joinpath(directory, "stages.csv"))
        println(
            row.name,
            " | ",
            row.status,
            " | objective=",
            row.objective_kind,
            ": ",
            row.solver_objective,
            " | cost=",
            row.operating_cost,
            " | flow distance=",
            row.flow_distance,
            " | seconds=",
            row.elapsed_sec,
        )
    end
    println("Stage comparison only: distance/slack bounds are not operating-cost bounds.")
elseif action=="plot"
    include("plot_r3.jl")
    output=length(ARGS)>2 ? ARGS[3] :
           joinpath(directory, "figures-"*Dates.format(now(UTC), "yyyymmddTHHMMSS"))
    println(plot_r3_run(directory; output))
else
    error("未知R3操作")
end
