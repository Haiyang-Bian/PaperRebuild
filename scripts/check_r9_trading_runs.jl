# 只读保存记录；不启动优化器、不改写失败判定。
using PaperRebuild, TOML
VERSION==v"1.12.6" || error("Expected Julia 1.12.6")
length(ARGS)>=2 && first(ARGS) in ("check", "compare") ||
    error("usage: check_r9_trading_runs.jl check|compare RUN_DIRECTORY [...]")
action, paths=first(ARGS), ARGS[2:end]
if action=="compare"
    length(paths)>=2 || error("Comparison needs at least two runs")
    TOML.print(stdout, compare_r9_trading_runs(paths); sorted = true)
else
    for path in paths
        x=read_r9_trading_run(path)
        println(
            "Frozen archive replay: ",
            x.result["run_id"],
            "; status=",
            x.result["status"],
            "; model=",
            x.validation["model_pass"],
            "; electric_original=",
            x.validation["electric_original_pass"],
            "; heat_envelope=",
            x.validation["heat_energy_mass_pass"],
            "; ledger=",
            x.validation["ledger_pass"],
            "; cost_complete=",
            x.validation["cost_optimization_complete"],
            "; full_thermal=false",
        )
    end
end
