# VS Code和命令行共用：不依赖编辑器中的隐式运行状态。
using TOML, Dates
root = normpath(joinpath(@__DIR__, ".."))
action = isempty(ARGS) ? "validate" : ARGS[1]
runs_root = joinpath(root, "results", "runs")
function latest_r2()
    candidates = filter(
        p -> isfile(joinpath(p, "metadata.toml")) && startswith(basename(p), "r2-"),
        readdir(runs_root; join = true),
    )
    isempty(candidates) && error("尚无R2运行，请先执行案例任务")
    return last(sort(candidates; by = p -> TOML.parsefile(joinpath(p, "metadata.toml"))["utc"]))
end
if action == "validate"
    @eval using PaperRebuild
    dir = length(ARGS)>1 ? ARGS[2] : latest_r2()
    run = read_r2_run(dir)
    report = validate_r2_solution(run.case, run.result)
    println(
        "run=",
        basename(dir),
        " model_pass=",
        report.model_pass,
        " physics_pass=",
        report.original_physics_pass,
    )
    report.model_pass || exit(1)
elseif action == "plot"
    include("plot_r2.jl")
    dir = length(ARGS)>1 ? ARGS[2] : latest_r2()
    output = joinpath(dir, "figures-"*Dates.format(now(UTC), "yyyymmddTHHMMSS"))
    println(plot_r2_run(dir; output))
elseif action == "compare"
    @eval using PaperRebuild, CSV
    length(ARGS) == 3 || error("compare需要两个明确的运行目录；不能猜测同口径参考")
    comparison = compare_r2_runs(ARGS[2], ARGS[3])
    println(
        "status=",
        comparison.status,
        " same_model=",
        comparison.same_model,
        " cost_difference=",
        comparison.cost_difference,
    )
else
    error("未知任务：$action")
end
