# VS Code 便捷入口；终端也可显式传入运行目录。只选时间最新记录，不筛掉失败。
isempty(ARGS) && error("用法：scripts/r1_task.jl validate|plot [运行目录]")
action = ARGS[1]
root = normpath(joinpath(@__DIR__, ".."))
if length(ARGS) >= 2
    dir = ARGS[2]
else
    runs = joinpath(root, "results", "runs")
    candidates = sort(filter(p -> isfile(joinpath(p, "metadata.toml")), readdir(runs; join = true)))
    isempty(candidates) && error("尚无保存的 R1 运行；请先执行 R1 micro case")
    dir = last(candidates)
end
println("Selected saved run: ", basename(dir))
empty!(ARGS)
push!(ARGS, dir)
if action == "validate"
    include("validate_r1.jl")
elseif action == "plot"
    include("plot_r1.jl")
    println(PaperRebuild.plot_r1_run(dir))
else
    error("未知操作 $action")
end
