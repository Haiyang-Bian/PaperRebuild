using CSV, TOML, SHA, Statistics, CairoMakie

# 仅处理已经保存并独立核验的图源；不调用任何优化器。
length(ARGS)==1 || error("usage: summarize_r3_v3.jl SUMMARY_DIRECTORY")
root=abspath(only(ARGS))
isfile(joinpath(root, "figure-config.toml")) || error("30例报告尚未完成")
rows=collect(CSV.File(joinpath(root, "comparison.csv")))
length(rows)==30 || error("正式比较必须包含全部30例")
length(unique(x.id for x in rows))==30 || error("重复运行ID")
cfg=TOML.parsefile(joinpath(root, "frozen.toml"))
Set(x.id for x in rows)==Set(x["id"] for x in cfg["entries"]) || error("冻结条目不一致")
oldroot=joinpath(
    @__DIR__,
    "..",
    "results",
    "summaries",
    "r3-v2",
    "r3-v2-combined-20260917T095056-767e69d2",
)
statistics=NamedTuple[]
for name in ("single-source", "two-source")
    group=[
        only(x for x in rows if x.id==name*"-"*suffix) for
        suffix in ("schpd", "case_fixed", "box25", "box50", "box75")
    ]
    for version in ("v2", "v3")
        pass=version=="v3" ? [x.physical_pass for x in group] : [x.v2_physical_pass for x in group]
        costs=[version=="v3" ? x.cost : x.v2_cost for (x, ok) in zip(group, pass) if ok]
        times=version=="v3" ? [x.elapsed_sec for x in group] :
              [
            only(y for y in CSV.File(joinpath(oldroot, "comparison.csv")) if y.id==x.id).elapsed_sec
            for x in group
        ]
        push!(
            statistics,
            (
                case = name,
                version,
                count = length(group),
                physical_pass = count(pass),
                best_cost = isempty(costs) ? missing : minimum(costs),
                median_cost = isempty(costs) ? missing : median(costs),
                worst_cost = isempty(costs) ? missing : maximum(costs),
                best_sec = minimum(times),
                median_sec = median(times),
                worst_sec = maximum(times),
                local_stationarity = version=="v3" ?
                                     count(x.local_stationarity_checked for x in group) : missing,
                outer_converged = version=="v3" ? count(x.outer_converged for x in group) : missing,
            ),
        )
    end
end
CSV.write(joinpath(root, "five-initial-statistics.csv"), statistics)
ablations=NamedTuple[]
for e in cfg["entries"]
    e["group"]=="ablation" || continue
    a=only(x for x in rows if x.id==e["id"])
    b=only(x for x in rows if x.id==e["paired_id"])
    a.input_sha256==b.input_sha256 && a.initial_flow_sha256==b.initial_flow_sha256 ||
        error("消融输入改变")
    push!(
        ablations,
        (
            id = a.id,
            baseline = b.id,
            input_sha256 = a.input_sha256,
            initial_flow_sha256 = a.initial_flow_sha256,
            disabled = e["physical_recovery"] ? "stationarity_check" : "physical_recovery",
            baseline_physical = b.physical_pass,
            ablation_physical = a.physical_pass,
            baseline_cost = b.cost,
            ablation_cost = a.cost,
            cost_change = ismissing(a.cost)||ismissing(b.cost) ? missing : a.cost-b.cost,
            baseline_stop = b.outer_status,
            ablation_stop = a.outer_status,
            baseline_stationarity = b.local_stationarity_checked,
            ablation_stationarity = a.local_stationarity_checked,
            baseline_iterations = b.iterations,
            ablation_iterations = a.iterations,
            baseline_sec = b.elapsed_sec,
            ablation_sec = a.elapsed_sec,
        ),
    )
end
length(ablations)==6 || error("消融必须有6项")
CSV.write(joinpath(root, "ablations.csv"), ablations)

for id in ("two-source-schpd", "two-source-VF_CT-pg", "single-delay-switch")
    sources=NamedTuple[]
    for (version, folder) in (("v2", oldroot), ("v3", root))
        for row in CSV.File(joinpath(folder, id, "F06-source.csv"))
            push!(sources, merge((version = version,), NamedTuple(row)))
        end
    end
    target=joinpath(root, id)
    CSV.write(joinpath(target, "F06-v2-v3-source.csv"), sources)
    fig=Figure(size = (1300, 800), fontsize = 15)
    Label(fig[0, 1:2], "Synthetic frozen input | "*id*" | v2 / v3", fontsize = 18)
    for (pos, field, title, unit, scale) in (
        ((1, 1), :cost, "Relaxed dispatch cost", "currency", identity),
        ((1, 2), :diagnostic, "Diagnostic objective", "dimensionless", identity),
        (
            (2, 1),
            :local_direction,
            "Local direction (not physical stationarity)",
            "dimensionless",
            log10,
        ),
        ((2, 2), :trust_radius, "Local trust radius", "dimensionless", identity),
    )
        ax=Axis(fig[pos...]; title, xlabel = "Outer iteration", ylabel = unit, yscale = scale)
        plotted=false
        for (version, color, style) in (("v2", :darkorange, :solid), ("v3", :steelblue, :dash))
            data=filter(
                x->x.version==version &&
                   !ismissing(getproperty(x, field)) &&
                   isfinite(getproperty(x, field)),
                sources,
            )
            isempty(data) && continue
            ys=[
                scale==log10 ? max(getproperty(x, field), 1e-12) : getproperty(x, field) for
                x in data
            ]
            scatterlines!(
                ax,
                [x.iteration for x in data],
                ys;
                color,
                linestyle = style,
                markersize = 4,
                label = version,
            )
            plotted=true
        end
        plotted && axislegend(ax; position = :rt)
    end
    Label(
        fig[3, 1:2],
        "Local physical restoration uses separate trial axes. Coincident curves are retained.",
        fontsize = 12,
    )
    for ext in ("png", "svg")
        save(joinpath(target, "F06-v2-v3."*ext), fig)
    end
end
checks=Dict{String,Any}(
    "schema"=>"r3-v3-summary-v1",
    "origin"=>"synthetic",
    "reoptimized"=>false,
    "runs"=>30,
    "paired_v2_comparison_sha256"=>bytes2hex(sha256(read(joinpath(oldroot, "comparison.csv")))),
)
for group in ("robustness", "modes", "ablation")
    rr=filter(x->x.group==group, rows)
    checks[group]=Dict(
        "count"=>length(rr),
        "physical_pass"=>count(x.physical_pass for x in rr),
        "outer_converged"=>count(x.outer_converged for x in rr),
        "local_stationarity_checked"=>count(x.local_stationarity_checked for x in rr),
    )
end
open(io->TOML.print(io, checks; sorted = true), joinpath(root, "statistics.toml"), "w")
println(checks)
println("30例配对、6项消融及v2/v3图源完成；未重新求解。")
