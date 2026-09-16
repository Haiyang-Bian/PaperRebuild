using JSON
root = normpath(joinpath(@__DIR__, ".."));
path = joinpath(root, ".vscode", "tasks.json")
previous = read(path, String);
config = JSON.parse(previous; dicttype = Dict{String,Any})
additions = Any[]
for (label, environment, script, extra) in (
    ("R2 mapping check", ".", "scripts/check_ch03.jl", String[]),
    ("R2 tests", ".", "test/r2.jl", String[]),
    (
        "R2 open fixed WMM",
        ".",
        "scripts/run_r2.jl",
        ["single-source", "wmm_checked_v1", "--fixed", "--open"],
    ),
    ("R2 variable WMM", "tools/solvers", "scripts/run_r2.jl", ["single-source", "wmm_checked_v1"]),
    ("R2 SCHPD", "tools/solvers", "scripts/run_r2.jl", ["two-source", "schpd_mc_v1"]),
    ("R2 validate saved", ".", "scripts/r2_task.jl", ["validate"]),
    ("R2 redraw", "docs", "scripts/r2_task.jl", ["plot"]),
    ("R2 comparison experiments", "tools/solvers", "scripts/experiment_r2.jl", String[]),
    ("R2 comparison report", "docs", "scripts/report_r2.jl", String[]),
)
    name = "PaperRebuild: "*label
    any(t -> t["label"] == name, config["tasks"]) && continue
    push!(
        additions,
        Dict(
            "label"=>name,
            "type"=>"process",
            "command"=>"julia",
            "args"=>vcat(["+1.12.6", "--startup-file=no", "--project="*environment, script], extra),
            "options"=>Dict("cwd"=>"\${workspaceFolder}"),
            "problemMatcher"=>String[],
        ),
    )
end
if !isempty(additions)
    ending = match(r"\n  \]\s*\}\s*$", previous)
    isnothing(ending) && error("任务JSON布局改变，请保留人工字段后调整")
    entries = [join("    " .* split(JSON.json(t; pretty = 2), '\n'), "\n") for t in additions]
    updated =
        rstrip(previous[1:prevind(previous, ending.offset)])*",\n"*join(entries, ",\n")*previous[ending.offset:end]
    JSON.parse(updated)["tasks"] == vcat(config["tasks"], additions) || error("未保留既有任务")
    read(path, String) == previous || error("文件被其他会话修改")
    write(path, updated)
end
