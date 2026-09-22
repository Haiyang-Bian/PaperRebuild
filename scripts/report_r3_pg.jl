using PaperRebuild, TOML, CSV, SHA, Dates, UUIDs
include("plot_r3_pg.jl")
length(ARGS)==1 || error("usage: report_r3_pg.jl SAVED_STUDY_TOML")
studyfile=abspath(only(ARGS))
study=TOML.parsefile(studyfile)
root=normpath(joinpath(@__DIR__, ".."))
id=study["batch"]*"-"*string(uuid4())[1:8]
dest=joinpath(root, "results", "summaries", "r3-pg", id)
mkpath(dest)
cp(studyfile, joinpath(dest, "study.toml"))
cp(joinpath(dirname(studyfile), "config.toml"), joinpath(dest, "config.toml"))
table=NamedTuple[]
failures=NamedTuple[]
initials=Dict{String,Any}()
figures=Pair{String,String}[]
for entry in study["runs"]
    dir=joinpath(dirname(studyfile), entry["directory"])
    loaded=read_r3_run(dir)
    c, r, meta=loaded.case, loaded.result, loaded.metadata
    haskey(r, "initial_flow") && (
        initials[entry["id"]]=(
            flow = PaperRebuild.r3_matrix(r["initial_flow"]),
            tolerance = 1e-6*(1+maximum(p["flow_max"] for p in c.data["heat"]["pipes"])),
        )
    )
    final=r["final_stage"]>0 ? r["stages"][r["final_stage"]] : nothing
    if isnothing(final) && !isempty(r["iterations"])
        row=last(r["iterations"])
        stage=r["stages"][row["stage"]]
        if row["mode"]=="diagnostic" && haskey(stage, "values")
            v=stage["values"]
            for (i, x) in enumerate(stage["elastic_rows"])
                residual=x["scale"]*abs(v["elastic_positive"][i]-v["elastic_negative"][i])
                tolerance=x["unit"]=="MW" ? 1e-6*(1+c.data["electric"]["grid_max_MW"]) : 1e-4
                push!(
                    failures,
                    (
                        id = entry["id"],
                        iteration = row["iteration"],
                        equation = x["equation"],
                        entity = x["entity"],
                        time = x["t"],
                        unit = x["unit"],
                        residual,
                        tolerance,
                        ratio = residual/tolerance,
                    ),
                )
            end
        end
    end
    firstdispatch=findfirst(
        x->get(x, "model_pass", false) && get(x, "objective_kind", "")=="operating_cost",
        r["stages"],
    )
    firstcost=isnothing(firstdispatch) ? missing : r["stages"][firstdispatch]["operating_cost"]
    cost=isnothing(final) ? missing : final["operating_cost"]
    push!(
        table,
        (
            id = entry["id"],
            case = entry["case"],
            initialization = entry["initialization"],
            physical_pass = loaded.validation.physical_pass,
            outer_status = r["outer_status"],
            outer_converged = r["outer_converged"],
            iterations = length(r["iterations"]),
            accepted = count(x->x["accepted"], r["iterations"]),
            first_feasible_cost = firstcost,
            final_cost = cost,
            elapsed_sec = get(r, "total_elapsed_sec", r["elapsed_sec"]),
            initial_flow_sha256 = get(r, "initial_flow_sha256", "none"),
        ),
    )
    sub=joinpath(dest, entry["id"])
    mkdir(sub)
    cp(joinpath(dir, "case.toml"), joinpath(sub, "case.toml"))
    trace=[
        (
            iteration = x["iteration"],
            mode = x["mode"],
            merit = x["merit"],
            accepted = x["accepted"],
            step = get(x, "step", missing),
            projected_gradient = get(x, "projected_gradient_norm", missing),
            smooth = get(x, "smooth", false),
            active_changed = get(x, "active_set_changed", false),
            trials = length(x["trials"]),
        ) for x in r["iterations"]
    ]
    isempty(trace) || CSV.write(joinpath(sub, "iterations.csv"), trace)
    provenance=Dict(
        "schema"=>"r3-pg-summary-v1",
        "origin"=>"synthetic",
        "run_id"=>meta["run_id"],
        "input_sha256"=>c.sha256,
        "run_sha256"=>meta["artifacts"]["run.toml"],
        "source_hashes"=>r["source_hashes_at_solve"],
        "full_evidence"=>"local immutable run; hashes retained",
        "physical_pass"=>loaded.validation.physical_pass,
        "outer_status"=>r["outer_status"],
    )
    open(io->TOML.print(io, provenance; sorted = true), joinpath(sub, "provenance.toml"), "w")
    if !isnothing(final)
        compact=deepcopy(final)
        pop!(compact, "sensitivity", nothing)
        open(io->TOML.print(io, compact; sorted = true), joinpath(sub, "final-solution.toml"), "w")
    end
    if entry["id"] in
       ("single-source-schpd", "two-source-schpd", "single-low-flow", "single-delay-switch")
        output=plot_r3_pg_run(dir; output = joinpath(sub, "figures"))
        asset=joinpath(root, "docs", "src", "assets", "r3-pg", id, entry["id"])
        mkpath(asset)
        for file in readdir(output)
            endswith(file, ".svg") || continue
            cp(joinpath(output, file), joinpath(asset, file))
            push!(
                figures,
                entry["id"]=>replace(
                    relpath(joinpath(asset, file), joinpath(root, "docs", "src")),
                    '\\'=>'/',
                ),
            )
        end
    end
end
CSV.write(joinpath(dest, "comparison.csv"), table)
isempty(failures) || CSV.write(joinpath(dest, "failure-diagnostics.csv"), failures)
io=IOBuffer()
println(
    io,
    "# R3 投影梯度实验结果\n\n合成案例；运行批次 `",
    study["batch"],
    "`。本页由保存数值生成，不重新求解。\n",
)
println(
    io,
    "初值、局部试探开关和预算在计算前冻结。五初值统计包含近似重复投影结果；首例含编译开销、后续为同进程运行，耗时不是受控性能比较。不据此宣称论文同输入复现、全局最优或速度优势。\n",
)
println(
    io,
    "| 案例 | 物理A1 | 停止原因 | 轮数/接受步 | 首个可行费用 | 最终费用 | 秒 |\n|---|---|---|---|---|---|---|",
)
for x in table
    println(
        io,
        "|",
        x.id,
        "|",
        x.physical_pass,
        "|",
        x.outer_status,
        "|",
        x.iterations,
        "/",
        x.accepted,
        "|",
        x.first_feasible_cost,
        "|",
        x.final_cost,
        "|",
        round(x.elapsed_sec; digits = 2),
        "|",
    )
end
println(
    io,
    "\n## 五初值汇总\n\n统计只覆盖schpd、case_fixed、box25、box50、box75；最坏/中位/最好费用只在物理通过的运行中计算，同时保留失败数量。\n",
)
statistics=NamedTuple[]
median_sorted(x) = isodd(length(x)) ? x[cld(length(x), 2)] : (x[length(x)÷2]+x[length(x)÷2+1])/2
for name in ("single-source", "two-source")
    rows=filter(x->x.case==name && x.id==name*"-"*x.initialization, table)
    costs=sort([x.final_cost for x in rows if x.physical_pass])
    times=sort([x.elapsed_sec for x in rows])
    isempty(rows) && continue
    representatives=Any[]
    for row in rows
        a=initials[row.id]
        any(maximum(abs, a.flow-b)<=a.tolerance for b in representatives) ||
            push!(representatives, a.flow)
    end
    stats=(
        case = name,
        runs = length(rows),
        physical_pass = length(costs),
        distinct_initials = length(unique(x.initial_flow_sha256 for x in rows)),
        distinct_within_A1 = length(representatives),
        best_cost = isempty(costs) ? missing : first(costs),
        median_cost = isempty(costs) ? missing : median_sorted(costs),
        worst_cost = isempty(costs) ? missing : last(costs),
        best_sec = first(times),
        median_sec = median_sorted(times),
        worst_sec = last(times),
    )
    push!(statistics, stats)
    println(
        io,
        "- **",
        name,
        "**：物理通过 ",
        stats.physical_pass,
        "/",
        stats.runs,
        "；不同初值哈希 ",
        stats.distinct_initials,
        "，按原有流量A1区分为 ",
        stats.distinct_within_A1,
        " 组（固定初值与box50近似重复）",
        "；费用最好/中位/最坏 ",
        stats.best_cost,
        " / ",
        stats.median_cost,
        " / ",
        stats.worst_cost,
        "；耗时最小/中位/最大 ",
        stats.best_sec,
        " / ",
        stats.median_sec,
        " / ",
        stats.worst_sec,
        " s。",
    )
end
CSV.write(joinpath(dest, "statistics.csv"), statistics)
println(io, "\n## 未恢复案例与局部半空间对照\n")
for name in unique(x.id for x in failures)
    rows=filter(x->x.id==name, failures)
    worst=rows[argmax([x.ratio for x in rows])]
    println(
        io,
        "- **",
        name,
        "**：末次诊断最大超限比对应式",
        worst.equation,
        "，实体",
        worst.entity,
        "，时段",
        worst.time,
        "；残差",
        worst.residual,
        " ",
        worst.unit,
        "，A1阈值",
        worst.tolerance,
        "。",
    )
end
println(
    io,
    "\n容量反例的10 MW需求超过端口输入上界0.315 MW，这是解析不可行证据；PG本身仅报告停滞。时延切换例未恢复可行，不能由局部停滞推出全局无解，也不能因剩余残差接近阈值就改判通过。\n",
)
println(
    io,
    "单源、双源有/无局部半空间运行的初始流量已逐元素核对完全相同。费用对照见上表：半空间在本批不表现为一致改善，不能单凭一组结果宣称它总是有效。\n",
)
println(
    io,
    "\n## 如何评价\n\n物理可行、费用下降与外层停止条件满足是三项独立事实。`line_search_stalled`、`untrusted_sensitivity`、时限或轮数上限都不等于收敛或已证明无解。费用比较从首个详细子问题可行解开始，不能把不可执行的SCHPD低费用当作基准收益。\n",
)
println(
    io,
    "原始对偶、所有试探、模型残差及源码快照在本地运行保留；公开摘要包括案例、最终数值、轨迹、来源哈希及图源CSV。结果摘要目录：`results/summaries/r3-pg/",
    id,
    "`。\n",
)
for (name, path) in figures
    println(
        io,
        "### ",
        name,
        " · ",
        basename(path),
        "\n\n![",
        name,
        " ",
        basename(path),
        "](",
        path,
        ")\n",
    )
end
write(joinpath(root, "docs", "src", "ch03-r3-pg-results.md"), rstrip(String(take!(io)))*"\n")
println(dest)
