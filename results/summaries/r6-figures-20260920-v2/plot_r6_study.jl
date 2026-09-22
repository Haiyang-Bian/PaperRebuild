using CairoMakie, CSV, TOML, SHA

"""从R6封存统计及压力轨迹绘制F17–F19。只读输入；新目录保存图源、脚本和图，不重新求解。"""
function plot_r6_study(input, output)
    ispath(output) && error("重绘必须使用新目录")
    hashfile(p) = bytes2hex(sha256(read(p)))
    meta = TOML.parsefile(joinpath(input, "public.toml"))
    identity = hashfile(joinpath(input, "public.toml"))
    identity == strip(read(joinpath(input, "public.sha256"), String)) || error("证据包清单被改")
    meta["origin"] == "synthetic" && meta["solver_reexecuted"] === false || error("证据类型错误")
    for (rel, h) in meta["files"]
        hashfile(joinpath(input, rel)) == h || error("图源改变：$rel")
    end
    reports = TOML.parsefile(joinpath(input, "tables/report.toml"))
    days = reduce(
        vcat,
        [
            collect(CSV.File(joinpath(input, "tables", f))) for
            f in sort(collect(keys(reports["tables"]))) if startswith(f, "days")
        ],
    )
    tests = filter(r -> r.split == "test", days)
    risk =
        filter(r -> r.split == "test", collect(CSV.File(joinpath(input, "tables/risk-cost.csv"))))
    pairs = collect(CSV.File(joinpath(input, "tables/paired-cost.csv")))
    hourly = collect(CSV.File(joinpath(input, "hourly.csv")))
    temperatures = collect(CSV.File(joinpath(input, "temperatures.csv")))
    methods = ["D", "SP", "RO", "DRO", "CCP", "DRJCC"]
    colors = ["#0072B2", "#009E73", "#E69F00", "#CC79A7", "#D55E00", "#000000"]
    styles = [:solid, :dash, :dot, :dashdot, :dashdotdot, :solid]
    all(count(r->r.method==m, tests)==1000 for m in methods) || error("测试日数不足")
    mkpath(output)
    for (name, rows) in (
        ("test-costs.csv", tests),
        ("risk.csv", risk),
        ("paired-cost.csv", pairs),
        ("hourly.csv", hourly),
        ("temperatures.csv", temperatures),
    )
        CSV.write(joinpath(output, name), rows)
    end
    set_theme!(Theme(font = "DejaVu Sans", fontsize = 15))
    caption = "Synthetic | "*meta["batch_id"]*" | frozen source "*meta["source_commit"][1:7]
    figures = String[]
    function savefigure(name, figure)
        for extension in ("png", "pdf")
            filename=name*"."*extension
            save(joinpath(output, filename), figure)
            push!(figures, filename)
        end
    end

    f = Figure(size = (1700, 850))
    Label(
        f[0, 1:2],
        caption*"\nF17: 1000 common independent synthetic days per method; complete-future daily dispatch",
        tellwidth = false,
    )
    a = Axis(
        f[1, 1],
        xlabel = "Daily IES net payment (synthetic USD)",
        ylabel = "Empirical cumulative probability",
        title = "Negative values are net payments, not resource savings",
    )
    for (m, col, style) in zip(methods, colors, styles)
        x=sort([r.net_cost_USD for r in tests if r.method==m])
        stairs!(
            a,
            x,
            collect(1:length(x)) ./ length(x);
            color = col,
            linestyle = style,
            linewidth = 2.5,
            label = m,
            step = :post,
        )
    end
    axislegend(a; position = :lt)
    others=methods[1:5]
    b=Axis(
        f[1, 2],
        xlabel = "DRJCC minus other method (synthetic USD/day)",
        yticks = (1:5, others),
        title = "Paired mean differences and individual 95% bootstrap intervals",
    )
    for (i, m) in enumerate(others)
        r=only(filter(x->x.method_a==m&&x.method_b=="DRJCC", pairs))
        r.status=="complete_pairs"&&r.n==1000 || error("配对费用未完成")
        center, lo, hi=-r.mean_difference_USD, -r.upper_USD, -r.lower_USD
        rangebars!(
            b,
            [i],
            [lo],
            [hi];
            direction = :x,
            color = colors[i],
            whiskerwidth = 12,
            linewidth = 2,
        )
        scatter!(b, [center], [i]; color = colors[i], markersize = 12)
        text!(
            b,
            center,
            i+0.18;
            text = string(round(center; digits = 4)),
            align = (:center, :bottom),
            fontsize = 12,
        )
    end
    vlines!(b, [0]; color = :gray, linestyle = :dash)
    ylims!(b, 0.5, 5.6)
    Label(
        f[2, 1:2],
        "2000 paired-day bootstrap replicates; seed 2026091904. Intervals are not optimality bounds or simultaneous guarantees.",
        fontsize = 13,
        tellwidth = false,
    )
    savefigure("F17", f)

    g=Figure(size = (1450, 830))
    Label(
        g[0, 1],
        caption*"\nF18: joint indoor-comfort violation on held-out days",
        tellwidth = false,
    )
    ax=Axis(
        g[1, 1],
        xticks = (1:6, methods),
        ylabel = "Probability (%)",
        title = "Points: observed rates; caps: separate one-sided 95% exact bounds",
    )
    for (i, m) in enumerate(methods)
        r=only(filter(x->x.method==m, risk))
        y=100*r.violations/r.n
        rangebars!(
            ax,
            [i],
            [100*r.lower],
            [100*r.upper];
            color = colors[i],
            linewidth = 2,
            whiskerwidth = 15,
        )
        scatter!(ax, [i], [y]; color = colors[i], markersize = 14)
        text!(
            ax,
            i,
            100*r.upper+0.4;
            text = "$(r.violations)/$(r.n)\nunknown=$(r.unknown)\n$(r.risk_status)",
            align = (:center, :bottom),
            fontsize = 13,
        )
    end
    hlines!(ax, [5.0]; color = :black, linestyle = :dash, label = "epsilon = 5%")
    axislegend(ax; position = :rt)
    xlims!(ax, 0.5, 6.5)
    ylims!(ax, -0.2, 9.0)
    Label(
        g[2, 1],
        "A complete day is one sample. Zero observed violations is not zero population risk. Pressure cases are excluded.",
        fontsize = 13,
        tellwidth = false,
    )
    savefigure("F18", g)

    stress=[
        "zero_pv_sustained_up",
        "zero_pv_sustained_down",
        "clear_pv_sustained_up",
        "clear_pv_sustained_down",
    ]
    h=Figure(size = (1950, 1400))
    Label(
        h[0, 1],
        caption*"\nF19: all four deterministic stress days; no probability claim. Gray dashed curves show saved requests.",
        tellwidth = false,
    )
    panels=GridLayout(h[1, 1])
    rowgap!(panels, 28)
    stresslabels=[
        "Zero PV / sustained up",
        "Zero PV / sustained down",
        "Clear PV / sustained up",
        "Clear PV / sustained down",
    ]
    for (row, day) in enumerate(stress)
        tt=filter(x->x.day_id==day, temperatures)
        length(unique(x.building for x in tt))==1 || error("本图要求明确的单建筑；不能静默取第一栋")
        axes=[
            Axis(
                panels[row, j],
                xlabel = row==4 ? "Hour (interval end)" : "",
                ylabel = label,
                title = j==1 ? stresslabels[row]*"\n"*title : title,
                titlesize = 15,
            ) for (j, label, title) in (
                (1, "Indoor (deg C)", "Indoor temperature; dashed = comfort limits"),
                (2, "Building heat (MWh)", "State relative to initial building temperature"),
                (3, "Response (MW)", "Delivered; gray dashed = request"),
                (4, "Mismatch (MWh)", "Accumulated absolute delivery mismatch"),
            )
        ]
        rowsize!(panels, row, Relative(0.25))
        lo=unique(x.comfort_min_K-273.15 for x in tt)
        hi=unique(x.comfort_max_K-273.15 for x in tt)
        length(lo)==length(hi)==1 || error("舒适边界不同，须另画分组")
        hlines!(axes[1], [only(lo), only(hi)]; color = :gray, linestyle = :dash)
        for (i, m) in enumerate(methods)
            rr=sort(filter(x->x.day_id==day&&x.method==m, hourly); by = x->x.t)
            tr=sort(filter(x->x.method==m, tt); by = x->x.t)
            values=(
                [x.indoor_K-273.15 for x in tr],
                [x.building_relative_heat_MWh for x in tr],
                [x.delivered_MW for x in rr],
                [x.cumulative_mismatch_MWh for x in rr],
            )
            for j in 1:4
                lines!(
                    axes[j],
                    [x.time_end_h for x in rr],
                    values[j];
                    color = colors[i],
                    linestyle = styles[i],
                    linewidth = i==6 ? 2.8 : 1.8,
                    label = m,
                )
            end
            # 请求可能随方法不同，每项原值都绘出；相同值重叠不另加抖动。
            lines!(
                axes[3],
                [x.time_end_h for x in rr],
                [x.requested_MW for x in rr];
                color = (:gray, 0.5),
                linestyle = :dash,
            )
        end
        for ax in axes
            xlims!(ax, 1, 24)
        end
        if row==4
            Legend(h[2, 1], axes[1]; orientation = :horizontal, framevisible = false)
        end
    end
    Label(
        h[3, 1],
        "Each curve retains run_id in CSV. Relative building heat = C*(T-T_initial); no battery exists in this case. This is not total pipe energy.",
        fontsize = 13,
        tellwidth = false,
    )
    savefigure("F19", h)
    sourcefiles=filter(f->endswith(f, ".csv"), readdir(output))
    config=Dict(
        "schema"=>"r6-study-figures-v1",
        "origin"=>"synthetic",
        "batch_id"=>meta["batch_id"],
        "public_evidence_sha256"=>identity,
        "solver_reexecuted"=>false,
        "risk_bounds"=>"separate_one_sided_95_percent_not_simultaneous",
        "paired_interval"=>"individual_percentile_bootstrap_95_percent",
        "script_sha256"=>hashfile(@__FILE__),
        "run_ids"=>sort(unique(String(x.run_id) for x in vcat(tests, hourly))),
        "sources"=>Dict(f=>hashfile(joinpath(output, f)) for f in sourcefiles),
        "figures"=>Dict(f=>hashfile(joinpath(output, f)) for f in figures),
    )
    cp(@__FILE__, joinpath(output, "plot_r6_study.jl"))
    open(joinpath(output, "figure-config.toml"), "w") do io
        TOML.print(io, config; sorted = true)
    end
    identity==hashfile(joinpath(input, "public.toml")) || error("绘图期间输入改变")
    println("F17/F18/F19 saved as PNG/PDF with raw plot data; no optimization.")
end

if abspath(PROGRAM_FILE)==@__FILE__
    length(ARGS)==2 || error("usage: plot_r6_study.jl <public-evidence> <new-figure-dir>")
    plot_r6_study(ARGS...)
end
