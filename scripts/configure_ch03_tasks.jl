# 可重复执行，按稳定label增量添加任务；保留其他任务和根级字段。
using JSON
root = normpath(joinpath(@__DIR__, ".."))
path = joinpath(root, ".vscode", "tasks.json")
previous = read(path, String)
config = JSON.parse(previous; dicttype = Dict{String,Any})
additions = Any[]
for (label, environment, script, extra) in (
    ("Ch03 restore data tools", "tools/data", "scripts/bootstrap_data.jl", String[]),
    ("Ch03 collect data", "tools/data", "scripts/collect_ch03_data.jl", String[]),
    ("Ch03 validate data", "tools/data", "scripts/validate_ch03_data.jl", String[]),
    ("Ch03 data tests", "tools/data", "test/ch03_data.jl", String[]),
    ("Ch03 data plots", "docs", "scripts/ch03_task.jl", ["plot"]),
)
    full = "PaperRebuild: " * label
    any(t -> t["label"] == full, config["tasks"]) && continue
    push!(
        additions,
        Dict(
            "label" => full,
            "type" => "process",
            "command" => "julia",
            "args" =>
                vcat(["+1.12.6", "--startup-file=no", "--project=" * environment, script], extra),
            "options" => Dict("cwd" => "\${workspaceFolder}"),
            "problemMatcher" => String[],
        ),
    )
end
isempty(additions) && exit()
# 仅追加到现有tasks数组末尾，避免重排人工字段；当前项目tasks必须为根级最后字段。
ending = match(r"\n  \]\s*\}\s*$", previous)
isnothing(ending) && error("tasks布局变更，请人工检查后调整追加位置")
prefix = rstrip(previous[1:prevind(previous, ending.offset)])
entries = [join("    " .* split(JSON.json(t; pretty = 2), '\n'), "\n") for t in additions]
updated = prefix * ",\n" * join(entries, ",\n") * previous[ending.offset:end]
JSON.parse(updated)["tasks"] == vcat(config["tasks"], additions) || error("新增任务未保持原配置")
read(path, String) == previous || error("任务文件被其他会话修改，请重新核对")
write(path, updated)
