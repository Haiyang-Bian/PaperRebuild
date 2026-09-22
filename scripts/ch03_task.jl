# VS Code任务包装：始终选择最后一次数据检查，包括失败记录，不能悄悄选一个成功运行。
isempty(ARGS) && error("用法：scripts/ch03_task.jl plot [保存目录]")
action = popfirst!(ARGS)
if isempty(ARGS)
    folder = joinpath(@__DIR__, "..", "data", "processed", "ch03")
    candidates =
        isdir(folder) ?
        sort(filter(p -> isfile(joinpath(p, "validation.toml")), readdir(folder; join = true))) :
        String[]
    isempty(candidates) && error("先运行 Ch03 validate data")
    push!(ARGS, last(candidates))
end
action == "plot" || error("未知操作")
include("plot_ch03_data.jl")
