using PaperRebuild, TOML, CSV, Dates, SHA, UUIDs
include("plot_r2.jl")
root = normpath(joinpath(@__DIR__, ".."))
if isempty(ARGS)
    candidates = [
        joinpath(p, "study.toml") for
        p in readdir(joinpath(root, "results", "runs"); join = true) if
        isfile(joinpath(p, "study.toml"))
    ]
    isempty(candidates) && error("先运行R2 comparison experiments")
    manifest_path = last(sort(candidates))
else
    manifest_path = abspath(ARGS[1])
end
study = TOML.parsefile(manifest_path)
target = joinpath(
    root,
    "results",
    "summaries",
    "r2-first-batch",
    study["batch"]*"-"*string(uuid4())[1:8],
)
mkpath(dirname(target));
mkdir(target)
paths = Dict{String,String}();
table = NamedTuple[]
failures = NamedTuple[]
for entry in study["runs"]
    haskey(entry, "directory") || continue
    source = joinpath(root, entry["directory"])
    run = read_r2_run(source)
    get(run.metadata, "source_snapshot_matches_solve", false) ||
        error("运行期间源码变化，拒绝提升摘要")
    checked = validate_r2_solution(run.case, run.result)
    dir = joinpath(target, entry["name"])
    mkdir(dir)
    paths[entry["name"]] = dir
    # 保存可独立回代的小型数值证据；原始日志和精确代码快照保留本地运行目录。
    for file in (
        "case.toml",
        "solution.toml",
        "metadata.toml",
        "validation.toml",
        "residuals.csv",
        "timeseries.csv",
    )
        isfile(joinpath(source, file)) && cp(joinpath(source, file), joinpath(dir, file))
    end
    model_rows = filter(r -> r.scope == "model", checked.rows)
    physics_rows = filter(r -> r.scope == "physics", checked.rows)
    for eq in unique(r.equation for r in physics_rows if !r.pass)
        bad = filter(r -> r.equation == eq, physics_rows)
        worst = bad[argmax([r.residual/r.tolerance for r in bad])]
        push!(
            failures,
            (
                name = entry["name"],
                equation = eq,
                entity = worst.entity,
                t = worst.t,
                residual = worst.residual,
                unit = worst.unit,
                tolerance = worst.tolerance,
                ratio = worst.residual/worst.tolerance,
            ),
        )
    end
    push!(
        table,
        (
            name = entry["name"],
            status = run.result["status"],
            objective = get(run.result, "objective", NaN),
            bound = get(run.result, "bound", NaN),
            gap = get(run.result, "relative_gap", NaN),
            model_pass = checked.model_pass,
            physics_pass = checked.original_physics_pass,
            model_max_ratio = isempty(model_rows) ? NaN :
                              maximum(r.residual/r.tolerance for r in model_rows),
            physics_max_ratio = isempty(physics_rows) ? NaN :
                                maximum(r.residual/r.tolerance for r in physics_rows),
        ),
    )
end
CSV.write(joinpath(target, "model-summary.csv"), table)
CSV.write(joinpath(target, "physical-failures.csv"), failures)
pairs = [
    ("single-fixed-open", "single-fixed-gurobi"),
    ("two-fixed-enumeration", "two-fixed-mip"),
    ("single-wmm", "single-schpd"),
    ("two-wmm", "two-schpd"),
    ("single-wmm", "ablation-heat-envelope"),
    ("single-wmm", "ablation-reference-loss"),
    ("single-wmm", "ablation-temperature"),
    ("two-wmm", "ablation-mixing"),
]
comparisons = Dict{String,Any}[]
for (a, b) in pairs
    haskey(paths, a) && haskey(paths, b) || continue
    comparison = compare_r2_runs(paths[a], paths[b])
    record = Dict{String,Any}("reference"=>a, "candidate"=>b, "status"=>comparison.status)
    if comparison.status == "compared"
        CSV.write(joinpath(target, a*"--"*b*".csv"), comparison.rows)
        record["same_model"] = comparison.same_model
        record["cost_difference"] = comparison.cost_difference
        ref, candidate = read_r2_run(paths[a]), read_r2_run(paths[b])
        record["cost_relative_difference"] =
            abs(comparison.cost_difference)/max(1, abs(ref.result["objective"]))
        if comparison.same_model
            record["A2_pass"] =
                record["cost_relative_difference"] <= 1e-4 &&
                get(ref.result, "relative_gap", Inf) <= 1e-4 &&
                get(candidate.result, "relative_gap", Inf) <= 1e-4
        end
        for q in ("tau_S_mix", "tau_R_mix", "H_port")
            record[q*"_max_abs_difference"] =
                maximum(abs(row.difference) for row in comparison.rows if row.quantity == q)
        end
    end
    push!(comparisons, record)
end
open(
    io -> TOML.print(
        io,
        Dict("study"=>study["batch"], "comparisons"=>comparisons, "paper_match"=>"blocked");
        sorted = true,
    ),
    joinpath(target, "comparisons.toml"),
    "w",
)
cp(manifest_path, joinpath(target, "study.toml"))
assets = joinpath(root, "docs", "src", "assets", "r2");
mkpath(assets)
plotted = String[]
for (candidate, reference) in
    (("single-wmm", nothing), ("single-schpd", "single-wmm"), ("two-schpd", "two-wmm"))
    haskey(paths, candidate) && haskey(read_r2_run(paths[candidate]).result, "values") || continue
    ref =
        isnothing(reference) ||
        !haskey(paths, reference) ||
        !haskey(read_r2_run(paths[reference]).result, "values") ? nothing : paths[reference]
    out = plot_r2_run(paths[candidate]; reference = ref)
    for file in filter(x -> endswith(x, ".svg"), readdir(out))
        name = candidate*"-"*file
        cp(joinpath(out, file), joinpath(assets, name); force = true)
        push!(plotted, name)
    end
end
# 第三层之外的单管道解析/变流量图源，明确沿用同一纯Julia回放器。
pipe_rows = NamedTuple[]
for (name, flows, epsilon) in (
    ("lossless", ones(4), 0.0),
    ("variable-flow", [1.0, 2.0, 0.5, 1.0], 0.2),
    ("lossy", ones(4), 0.2),
)
    inlet = [350.0, 360.0, 350.0, 350.0]
    r = replay_water_mass(
        inlet,
        flows,
        fill(340.0, 4),
        ones(4);
        mass_kg = 5400.0,
        dt_h = 1.0,
        epsilon_W_mK = epsilon,
    )
    for t in 1:4
        push!(
            pipe_rows,
            (
                scenario = name,
                t = t,
                time_h = Float64(t),
                inlet_K = inlet[t],
                outlet_K = r.outlet[t],
                flow_kg_s = flows[t],
                residence_s = r.residence_s[t],
            ),
        )
    end
end
CSV.write(joinpath(target, "pipe-response.csv"), pipe_rows)
pipefig = Figure(size = (1100, 730), fontsize = 16)
Label(pipefig[0, 1:2], "Synthetic single pipe | "*study["batch"], fontsize = 20)
tempaxis = Axis(pipefig[1, 1], xlabel = "Time (h)", ylabel = "Outlet temperature (K)")
flowaxis = Axis(pipefig[1, 2], xlabel = "Time (h)", ylabel = "Mass flow (kg/s)")
for scenario in unique(r.scenario for r in pipe_rows)
    rows = filter(r -> r.scenario == scenario, pipe_rows)
    scatterlines!(tempaxis, [r.time_h for r in rows], [r.outlet_K for r in rows]; label = scenario)
    scatterlines!(flowaxis, [r.time_h for r in rows], [r.flow_kg_s for r in rows]; label = scenario)
end
axislegend(tempaxis; position = :lt)
Label(
    pipefig[2, 1:2],
    "Stored mass 5400 kg; inlet step and 340 K history; dt = 1 h; pure cumulative-mass replay (no optimization).",
    fontsize = 13,
)
save(joinpath(target, "F05-single-pipe.svg"), pipefig)
save(joinpath(target, "F05-single-pipe.png"), pipefig)
open(
    io -> TOML.print(
        io,
        Dict(
            "origin"=>"synthetic",
            "batch"=>study["batch"],
            "mass_kg"=>5400.0,
            "dt_h"=>1.0,
            "area_m2"=>0.01,
            "rho_kg_m3"=>1000.0,
            "cp_J_kgK"=>4200.0,
            "ambient_K"=>293.0,
            "history_inlet_K"=>fill(340.0, 4),
            "history_flow_kg_s"=>ones(4),
            "inlet_K"=>[350.0, 360.0, 350.0, 350.0],
            "epsilon_W_mK"=>[0.0, 0.2, 0.2],
            "source_sha256"=>bytes2hex(sha256(read(joinpath(target, "pipe-response.csv")))),
        );
        sorted = true,
    ),
    joinpath(target, "single-pipe-figure.toml"),
    "w",
)
cp(joinpath(target, "F05-single-pipe.svg"), joinpath(assets, "F05-single-pipe.svg"); force = true)
pushfirst!(plotted, "F05-single-pipe.svg")
io = IOBuffer()
println(io, "# [R2 首批实验结果](@id ch03-r2-results)\n")
println(
    io,
    "<!-- GENERATED: scripts/report_r2.jl; evidence in results/summaries/r2-first-batch. -->\n",
)
println(
    io,
    "批次：`",
    study["batch"],
    "`；**全部为合成案例**，每实例预算",
    study["budget_per_instance_sec"],
    "秒。单线程、种子0；计时从进入solve_r2_case开始，包含内部建模与求解。进程启动/包加载及验证绘图另计，本批不作速度结论。\n",
)
println(
    io,
    "成本使用合成计价单位（单价/ MWh × MW × h），不对应实际币种，也不与论文成本直接比较。\n",
)
println(
    io,
    "源证据：`",
    replace(relpath(target, root), '\\'=>'/'),
    "`。公开摘要保留输入/解/哈希与逐式残差；完整日志和源码快照留在本地独立运行目录。\n",
)
println(
    io,
    "## 模型自身与原物理检查\n\n| 运行 | 停止状态 | 成本 | 模型A1 | 原关系A1 |\n| --- | --- | ---: | --- | --- |",
)
for row in table
    println(
        io,
        "| ",
        row.name,
        " | ",
        row.status,
        " | ",
        isfinite(row.objective) ? round(row.objective; digits = 6) : "—",
        " | ",
        row.model_pass,
        " | ",
        row.physics_pass,
        " |",
    )
end
println(
    io,
    "\n`false`不被隐藏：literal是原式阻断；有解运行的物理失败必须阅读残差分项，尤其水压锥松弛3-25、WMM回放、热功率乘积与混合温度。\n",
)
println(
    io,
    "## 默认版本的物理失败定位\n\n| 运行 | 关系 | 节点/管道 | 时段 | 最大残差 | 单位 | A1阈值 |\n| --- | --- | --- | ---: | ---: | --- | ---: |",
)
for row in failures
    row.name in ("single-wmm", "single-schpd", "two-wmm", "two-schpd") || continue
    println(
        io,
        "| ",
        row.name,
        " | ",
        row.equation,
        " | ",
        row.entity,
        " | ",
        row.t,
        " | ",
        round(row.residual; sigdigits = 5),
        " | ",
        row.unit,
        " | ",
        row.tolerance,
        " |",
    )
end
println(io, "\n完整失败位置见`physical-failures.csv`及各运行`residuals.csv`。阈值未随结果放宽。\n")
println(
    io,
    "## 同模型对照与近似分项\n\n| 参考 → 对照 | 同模型 | 成本差 | 温度最大差 S/R (K) | A2 |\n| --- | --- | ---: | ---: | --- |",
)
for r in comparisons
    r["status"] == "compared" || continue
    println(
        io,
        "| ",
        r["reference"],
        " → ",
        r["candidate"],
        " | ",
        r["same_model"],
        " | ",
        round(r["cost_difference"]; digits = 6),
        " | ",
        round(r["tau_S_mix_max_abs_difference"]; digits = 5),
        " / ",
        round(r["tau_R_mix_max_abs_difference"]; digits = 5),
        " | ",
        haskey(r, "A2_pass") ? r["A2_pass"] : "不适用",
        " |",
    )
end
println(
    io,
    "\n不同模型的温度差包含优化决策变化，不能全部解释为同一控制轨迹下的纯离散误差；逐运行WMM回放残差另列在F04/CSV。成本差不是最优间隙，松弛/近似低成本不证明经济性。\n",
)
println(io, "## 科学图：残差和温度/热功率对照\n")
for name in plotted
    println(io, "![", name, "](assets/r2/", name, ")\n")
end
println(
    io,
    "## 结论边界\n\n项目补全模型的求解、独立回代、同模型对照和绘图流程已执行。原式literal及论文数值匹配仍阻断；电/水松弛等式或热近似检查失败时，不能宣布原调度物理可行。R3的可行性恢复和论文规模数据闭合尚未实施。\n",
)
summary = rstrip(String(take!(io)))*"\n"
write(
    joinpath(target, "summary.md"),
    replace(summary, "(assets/r2/"=>"(../../../../docs/src/assets/r2/"),
)
write(joinpath(root, "docs", "src", "ch03-r2-results.md"), summary)
println("R2_REPORT=", replace(relpath(target, root), '\\'=>'/'))
