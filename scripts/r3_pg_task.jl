include("r3_setup.jl")
length(ARGS)>=2 || error("usage: r3_pg_task.jl validate|compare|plot RUN_DIR...")
action=first(ARGS)
if action=="plot"
    include("plot_r3_pg.jl")
    for dir in ARGS[2:end]
        println(plot_r3_pg_run(dir))
    end
else
    action in ("validate", "compare") || error("未知操作")
    for dir in ARGS[2:end]
        loaded=read_r3_run(dir)
        r=loaded.result
        r["algorithm"] in ("r3_pg_checked_v1", "r3_pg_checked_v2", "r3_cost_reference_v1") ||
            error("非R3算法运行")
        println(
            "run=",
            loaded.metadata["run_id"],
            " physical=",
            loaded.validation.physical_pass,
            " stop=",
            r["outer_status"],
            " iterations=",
            length(get(r, "iterations", Any[])),
            " final_stage=",
            r["final_stage"],
            " elapsed=",
            r["elapsed_sec"],
        )
        for row in get(r, "iterations", Any[])
            st=r["stages"][row["stage"]]
            kkt=get(get(st, "sensitivity", Dict()), "kkt", Dict())
            println((
                iteration = row["iteration"],
                mode = row["mode"],
                merit = row["merit"],
                accepted = row["accepted"],
                trials = length(row["trials"]),
                kkt = [
                    k=>get(kkt, k, missing) for
                    k in ("primal", "dual", "complementarity", "stationarity", "relative_gap")
                ],
            ))
        end
    end
end
