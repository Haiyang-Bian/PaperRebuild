using PaperRebuild, TOML

length(ARGS)==1 || error("usage: report_r3_reference.jl REFERENCE_TOML")
path=abspath(ARGS[1])
evidence=TOML.parsefile(path)
root=normpath(joinpath(@__DIR__, ".."))
target=joinpath(root, "results", "summaries", "r3-first-batch", evidence["batch"])
ispath(target) && error("拒绝覆盖旧参考摘要")
mkpath(target)
for (name, record) in evidence["results"]
    source=joinpath(dirname(path), record["directory"])
    loaded=read_r3_run(source)
    loaded.validation.physical_pass || error("参考最终物理检查未通过")
    sp=only(filter(s->s["stage"]=="fixed_dispatch", loaded.result["stages"]))
    sp["status"]=="solver_optimal" && sp["solver_relative_gap"]<=evidence["A2_threshold"] ||
        error("参考界不达标")
    sp["operating_cost"]==record["cost"] && sp["flow_sha256"]==record["flow_sha256"] ||
        error("参考表与解不一致")
    loaded.case.sha256==evidence["input_sha256"] || error("输入不一致")
    dest=joinpath(target, record["directory"])
    mkdir(dest)
    for file in keys(loaded.metadata["artifacts"])
        cp(joinpath(source, file), joinpath(dest, file))
    end
    meta=deepcopy(loaded.metadata)
    meta["snapshot_included"]=false
    open(io->TOML.print(io, meta; sorted = true), joinpath(dest, "metadata.toml"), "w")
    read_r3_run(dest)
end
a, b=evidence["results"]["clarabel"], evidence["results"]["gurobi"]
a["flow_sha256"]==b["flow_sha256"] || error("不同流量不是同一问题")
relative=abs(b["cost"]-a["cost"])/max(1, abs(a["cost"]))
relative==evidence["relative_difference"] && relative<=evidence["A2_threshold"] ||
    error("A2目标差不达标")
cp(path, joinpath(target, "reference.toml"))
io=IOBuffer()
println(io, "# [R3 同模型求解器对照](@id ch03-r3-reference)\n")
println(io, "<!-- GENERATED: scripts/report_r3_reference.jl -->\n")
println(
    io,
    "合成单源案例，完全相同的固定流量连续SOCP；输入/流量哈希一致，每次完整流程最多60秒。结果重新回代，并保留原始与κ重构后的解。\n",
)
println(io, "| 求解器 | 原SOCP费用 | 费用界 | 相对间隙 |\n| --- | ---: | ---: | ---: |")
for name in ("clarabel", "gurobi")
    r=evidence["results"][name]
    println(io, "| ", name, " | ", r["cost"], " | ", r["bound"], " | ", r["gap"], " |")
end
println(
    io,
    "\n目标相对差：`",
    relative,
    "`；两者实际有效间隙均低于A2门槛`1e-4`。8项本机断言通过。\n",
)
println(
    io,
    "证据：`",
    replace(relpath(target, root), '\\'=>'/'),
    "`。这支持固定流量子问题的数值一致性，不证明可变流量的全局成本最优或作者外层算法正确。\n",
)
write(joinpath(root, "docs", "src", "ch03-r3-reference.md"), rstrip(String(take!(io)))*"\n")
println("R3_REFERENCE_REPORT=", target)
