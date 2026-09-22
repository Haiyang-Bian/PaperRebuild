# VS Code 便捷入口；终端也可显式传入运行目录。只选时间最新记录，不筛掉失败。
using TOML, Dates

"""
    latest_r1_run(runs)

仅从默认`r1-`目录中选择元数据确认为R1、创建时间最新的记录；失败结果同样参加选择。
不使用目录的字典序或修改时间推断科研时序。自定义run ID请在任务中显式传入路径。
R1元数据损坏时明确报错，不通过跳过坏记录隐藏最新失败。
"""
function latest_r1_run(runs)
    candidates = Tuple{DateTime,String}[]
    isdir(runs) || error("尚无保存的R1运行；请先执行R1 micro case")
    for dir in readdir(runs; join = true)
        isdir(dir) && startswith(basename(dir), "r1-") || continue
        metadata = TOML.parsefile(joinpath(dir, "metadata.toml"))
        get(metadata, "scope", "") == "ch02 fixed-flow two-node subset" ||
            error("目录并非R1运行：" * basename(dir))
        push!(candidates, (DateTime(metadata["created_utc"]), dir))
    end
    isempty(candidates) && error("尚无保存的R1运行；请先执行R1 micro case")
    return last(sort(candidates))[2]
end

if abspath(PROGRAM_FILE) == @__FILE__
    length(ARGS) in (1, 2) || error("用法：scripts/r1_task.jl validate|plot [运行目录]")
    action = ARGS[1]
    action in ("validate", "plot") || error("未知操作 $action")
    root = normpath(joinpath(@__DIR__, ".."))
    dir = length(ARGS) == 2 ? ARGS[2] : latest_r1_run(joinpath(root, "results", "runs"))
    println("Selected saved run: ", basename(dir))
    empty!(ARGS)
    push!(ARGS, dir)
    if action == "validate"
        include("validate_r1.jl")
    else
        include("plot_r1.jl")
        println(PaperRebuild.plot_r1_run(dir))
    end
end
