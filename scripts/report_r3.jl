using PaperRebuild, CSV, TOML, Dates, UUIDs, SHA
include("plot_r3.jl")

length(ARGS)==1 || error("usage: report_r3.jl STUDY_TOML (explicit saved batch)")
root=normpath(joinpath(@__DIR__, ".."))
studyfile=abspath(ARGS[1])
study=TOML.parsefile(studyfile)
target=joinpath(
    root,
    "results",
    "summaries",
    "r3-first-batch",
    study["batch"]*"-"*string(uuid4())[1:8],
)
mkpath(target)
cp(studyfile, joinpath(target, "study.toml"))
assets=joinpath(root, "docs", "src", "assets", "r3")
mkpath(assets)
table=NamedTuple[]
stage_table=NamedTuple[]
figures=Tuple{String,String}[]
failures=NamedTuple[]
for entry in study["runs"]
    directory=joinpath(dirname(studyfile), entry["directory"])
    loaded=read_r3_run(directory)
    # 正式摘要要求保存时的科学源码哈希与运行开始时一致；旧失败证据也原样保留。
    for (p, hash) in loaded.result["source_hashes_at_solve"]
        get(loaded.metadata["source_hashes"], p, "")==hash || error("科学源码快照不一致：$p")
    end
    dest=joinpath(target, entry["directory"])
    mkdir(dest)
    for name in keys(loaded.metadata["artifacts"])
        cp(joinpath(directory, name), joinpath(dest, name))
    end
    meta=deepcopy(loaded.metadata)
    meta["snapshot_included"]=false
    meta["source_snapshot_location"]="original local run; source hashes retained in public summary"
    open(io->TOML.print(io, meta; sorted = true), joinpath(dest, "metadata.toml"), "w")
    check=read_r3_run(dest)
    result=check.result
    final=result["final_stage"]>0 ? result["stages"][result["final_stage"]] : nothing
    distance=isnothing(final) ? missing :
             PaperRebuild.r3_distance(
        check.case,
        PaperRebuild.r2_flow_matrix(check.case, final["values"]["m_pipe"]),
        PaperRebuild.r2_flow_matrix(check.case, result["initial_flow"]),
    )
    push!(
        table,
        (
            case = entry["id"],
            run_id = meta["run_id"],
            status = result["status"],
            physical_pass = check.validation.physical_pass,
            cost_complete = result["cost_optimization_complete"],
            flow_distance = distance,
            operating_cost = isnothing(final) ? missing : final["operating_cost"],
            elapsed_sec = result["elapsed_sec"],
        ),
    )
    if isfile(joinpath(dest, "stages.csv"))
        append!(
            stage_table,
            [
                merge((case = entry["id"],), NamedTuple(row)) for
                row in CSV.File(joinpath(dest, "stages.csv"))
            ],
        )
    end
    for (i, r) in enumerate(check.validation.stages), row in r.rows
        row.pass || push!(
            failures,
            merge((case = entry["id"], stage = i, name = result["stages"][i]["stage"]), row),
        )
    end
    plotdir=plot_r3_run(dest)
    for name in readdir(plotdir)
        endswith(name, ".svg") || continue
        publicname=entry["id"]*"-"*name
        cp(joinpath(plotdir, name), joinpath(assets, publicname); force = true)
        push!(figures, (entry["id"], publicname))
    end
end
CSV.write(joinpath(target, "cases.csv"), table)
isempty(stage_table) || CSV.write(joinpath(target, "stages.csv"), stage_table)
isempty(failures) || CSV.write(joinpath(target, "failures.csv"), failures)
value(x) = ismissing(x) ? "—" : x isa AbstractFloat ? string(round(x; digits = 6)) : string(x)
io=IOBuffer()
println(io, "# [R3 首批可行性闭环：实验结果](@id ch03-r3-results)\n")
println(io, "<!-- GENERATED: scripts/report_r3.jl; do not hand-edit numerical findings. -->\n")
println(
    io,
    "批次：`",
    study["batch"],
    "`。**全部为合成案例**；每个完整流程共享",
    study["budget_per_instance_sec"],
    "秒预算。线程1、种子0，A1门槛未放宽。\n",
)
println(
    io,
    "源证据：`",
    replace(relpath(target, root), '\\'=>'/'),
    "`。公开摘要保留配置、各阶段解、残差及输入/代码哈希；完整源码快照在本地独立运行目录。\n",
)
println(
    io,
    "成本为合成计价单位，非现实币种。成本优化完成只表示**该固定流量的详细调度**达到求解器最优终止，不是所有流量联合优化的全局最优。\n",
)
println(
    io,
    "## 最终判定\n\n| 案例 | 状态 | 物理A1 | 固定流量成本完成 | 流量改动D | 成本 | 耗时s |\n| --- | --- | --- | --- | ---: | ---: | ---: |",
)
for r in table
    println(
        io,
        "| ",
        join(
            value.((
                r.case,
                r.status,
                r.physical_pass,
                r.cost_complete,
                r.flow_distance,
                r.operating_cost,
                r.elapsed_sec,
            )),
            " | ",
        ),
        " |",
    )
end
println(
    io,
    "\n计时从流程入口开始，包含阶段建模和求解；启动、包加载、保存和绘图另计。本批不评价算法速度。\n",
)
println(
    io,
    "## 阶段对照\n\n| 案例 / 阶段 | 停止状态 | 目标类型 | 求解目标 | 运行成本 | 流量D | 模型A1 | 物理A1 |\n| --- | --- | --- | ---: | ---: | ---: | --- | --- |",
)
for r in stage_table
    println(
        io,
        "| ",
        join(
            value.((
                r.case*" / "*r.name,
                r.status,
                r.objective_kind,
                r.solver_objective,
                r.operating_cost,
                r.flow_distance,
                r.model_pass,
                r.physical_pass,
            )),
            " | ",
        ),
        " |",
    )
end
println(
    io,
    "\n目标界及实际间隙见`stages.csv`和每阶段原始TOML。`flow_distance`与`normalized_slack`的界不能解释为费用界；不同阶段的费用差也不是最优间隙。\n",
)
println(
    io,
    "## 怎样解释这些结果\n\n- SCHPD阶段是初值，其热关系误差保留在失败表；最终只接受详细模型及松弛前关系全部通过的候选。\n- 低流量例只说明边界内的流量仍可能无法供热；弹性目标大于零用于定位冲突，诊断解不能执行。\n- 容量反例负荷为10 MW；管道及端口上界1.5 kg/s、供水上界363 K、负荷回水313 K，对应端口上限0.315 MW，已在优化前构造为不可恢复。\n- 免费购电边界例移除网损的价格惩罚，用于检查电网锥不取等时的固定流量详细求解分支；这不是论文运行模式。\n- `infeasible_certified`与`time_limit_no_solution`、`repair_unresolved`分别保留。失败细目见`failures.csv`；无数值解的阶段不能画出残差。\n",
)
println(
    io,
    "## 科学图 F04 / F05\n\nF04覆盖全部阶段并标出A1阈值；详细图按公式、实体、时段展示最差24组，完整记录在图源CSV。F05对比初值/首个有解阶段与最终候选，虚线为独立质量回放。图中的阶段顺序不是梯度迭代。\n",
)
for (id, name) in figures
    endswith(name, "F04-detail.svg") && continue
    println(io, "![", id, " / ", name, "](assets/r3/", name, ")\n")
end
println(
    io,
    "## 交付边界\n\n已建立项目可行性闭环；原式台账覆盖3-1至3-66，但梯度、割平面与投影仍未实现。没有论文同输入数值匹配、完整四模式或论文规模性能证据，不生成F06/F07结论。下一批应在本批固定流量和诊断接口上推导可验证的灵敏度及投影更新。\n",
)
summary=rstrip(String(take!(io)))*"\n"
write(joinpath(root, "docs", "src", "ch03-r3-results.md"), summary)
write(
    joinpath(target, "summary.md"),
    replace(summary, "(assets/r3/"=>"(../../../../docs/src/assets/r3/"),
)
println("R3_REPORT=", replace(relpath(target, root), '\\'=>'/'))
