using PaperRebuild
length(ARGS)==1||error("参数：已保存IES运行目录")
x=read_r5_dispatch_run(only(ARGS))
println(
    x.result["run_id"],
    "; model=",
    x.validation["model_pass"],
    "; delivery=",
    x.validation["delivery_pass"],
    "; cost complete=",
    x.result["cost_optimization_complete"],
    "; no optimization performed",
)
