using JSON
root=normpath(joinpath(@__DIR__, ".."))
path=joinpath(root, ".vscode", "tasks.json")
previous=read(path, String)
config=JSON.parse(previous; dicttype = Dict{String,Any})
original=deepcopy(config)
for (label, env, script, args) in (
    ("R3 mapping check", ".", "scripts/check_ch03.jl", String[]),
    ("R3 tests", ".", "scripts/test_r3.jl", String[]),
    ("R3 open fixed case", ".", "scripts/experiment_r3.jl", ["single-fixed", "--open"]),
    ("R3 single SCHPD feasibility", "tools/solvers", "scripts/experiment_r3.jl", ["single-schpd"]),
    ("R3 formal experiments", "tools/solvers", "scripts/experiment_r3.jl", String[]),
    ("R3 validate saved", ".", "scripts/r3_task.jl", ["validate", "\${input:r3RunDirectory}"]),
    ("R3 stage comparison", ".", "scripts/r3_task.jl", ["stages", "\${input:r3RunDirectory}"]),
    ("R3 redraw", "docs", "scripts/r3_task.jl", ["plot", "\${input:r3RunDirectory}"]),
    ("R3 evidence report", "docs", "scripts/report_r3.jl", ["\${input:r3StudyManifest}"]),
)
    name="PaperRebuild: "*label
    any(t->t["label"]==name, config["tasks"]) && continue
    push!(
        config["tasks"],
        Dict(
            "label"=>name,
            "type"=>"process",
            "command"=>"julia",
            "args"=>vcat(["+1.12.6", "--startup-file=no", "--project="*env, script], args),
            "options"=>Dict("cwd"=>"\${workspaceFolder}"),
            "problemMatcher"=>String[],
        ),
    )
end
inputs=get!(config, "inputs", Any[])
for (id, description) in (
    ("r3RunDirectory", "R3运行目录（包含case.toml/run.toml/metadata.toml）"),
    ("r3StudyManifest", "已保存批次的study.toml路径"),
)
    any(x->x["id"]==id, inputs) && continue
    push!(inputs, Dict("id"=>id, "type"=>"promptString", "description"=>description))
end
# 验证新增任务没有改变已有任务及未知字段，写入前检查外部并发修改。
config["tasks"][1:length(original["tasks"])]==original["tasks"] || error("旧任务被修改")
all(config[k]==v for (k, v) in original if !(k in ("tasks", "inputs"))) || error("未知字段被修改")
read(path, String)==previous || error("任务文件被另一会话修改")
updated=JSON.json(config; pretty = 2)*"\n"
JSON.parse(updated)==config || error("任务JSON回读不一致")
updated==previous || write(path, updated)
println("R3 tasks configured; personal settings unchanged.")
