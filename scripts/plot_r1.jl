using PaperRebuild, CairoMakie
using TOML, CSV, SHA

# 独立绘图方法：只读已保存的解，不加载求解器，也不重新运行模型。
function PaperRebuild.plot_r1_run(dir::AbstractString; output = joinpath(dir, "figures"))
    saved = read_r1_run(dir)
    haskey(saved.result, "values") || error("无解运行不能绘制解轨迹")
    mkpath(output)
    d, s, id = saved.case.data, saved.result["values"], saved.metadata["run_id"]
    T, Δt = d["time"]["T"], d["time"]["dt_h"]
    subtitle = "Synthetic case | " * id
    figure_config = Dict(
        "run_id" => id,
        "origin" => "synthetic",
        "solution_sha256" => bytes2hex(sha256(read(joinpath(dir, "solution.toml")))),
        "input_sha256" => saved.case.sha256,
        "size_F01_F02" => [1100, 650],
        "size_F03" => [1100, 820],
        "size_F04" => [1300, 800],
        "julia" => string(VERSION),
        "renderer" => "CairoMakie",
        "renderer_version" => string(Base.pkgversion(CairoMakie)),
        "redraw_only" => true,
    )
    open(
        io -> TOML.print(io, figure_config; sorted = true),
        joinpath(output, "figure-config.toml"),
        "w",
    )
    emit(fig, name) =
        (save(joinpath(output, name * ".svg"), fig); save(joinpath(output, name * ".png"), fig))

    fig = Figure(size = (1100, 650))
    Label(fig[0, 1], "F01  Fixed electric and heat topology\n" * subtitle; tellwidth = false)
    ax = Axis(
        fig[1, 1],
        width = 1000,
        height = 490,
        limits = (0, 10, 0, 7),
        title = "Electric: MW / Mvar     Heat: kg/s / K",
    )
    hidedecorations!(ax)
    hidespines!(ax)
    for (ys, color) in ((5.5, :steelblue), (3.3, :tomato), (1.7, :teal))
        lines!(ax, [2, 8], [ys, ys]; color, linewidth = 4)
        scatter!(ax, [2, 8], [ys, ys]; color, markersize = 20)
    end
    text!(ax, 2, 6.3; text = "E1: grid", align = (:center, :center))
    text!(ax, 8, 6.3; text = "E2: CHP / PV / BS\nEB / HP / load", align = (:center, :center))
    text!(
        ax,
        5,
        5.9;
        text = "P, Q -> | r=$(d["electric"]["r_pu"]), x=$(d["electric"]["x_pu"]) pu",
        align = (:center, :center),
    )
    text!(ax, 2, 2.5; text = "H1: heat source\nCHP + EB + HP + HS", align = (:center, :center))
    text!(ax, 8, 2.5; text = "H2: building\nnetwork + local heater", align = (:center, :center))
    text!(ax, 5, 3.7; text = "Supply -> $(d["heat"]["m"]) kg/s", align = (:center, :center))
    text!(ax, 5, 1.2; text = "Return <- $(d["heat"]["m"]) kg/s", align = (:center, :center))
    text!(
        ax,
        5,
        0.4;
        text = "One pipe each way; L=$(d["heat"]["L"]) m; prescribed hydraulic point and explicit history",
        align = (:center, :center),
    )
    emit(fig, "F01-topology")
    CSV.write(
        joinpath(output, "F01-edges.csv"),
        [
            (network = "electric", from = 1, to = 2, quantity = 1.0, unit = "MVA base"),
            (network = "supply", from = 1, to = 2, quantity = d["heat"]["m"], unit = "kg/s"),
            (network = "return", from = 2, to = 1, quantity = d["heat"]["m"], unit = "kg/s"),
        ],
    )

    dev = d["devices"]
    ratio = chp_heat(1.0, dev["eta_G"], dev["eta_loss"])
    P_lo = ratio > 0 ? max(dev["P_CHP_min"], dev["H_CHP_min"] / ratio) : dev["P_CHP_min"]
    P_hi = ratio > 0 ? min(dev["P_CHP_max"], dev["H_CHP_max"] / ratio) : dev["P_CHP_max"]
    P = collect(range(P_lo, P_hi; length = 100))
    H = chp_heat.(P, dev["eta_G"], dev["eta_loss"])
    fig = Figure(size = (1100, 650))
    Label(
        fig[0, 1:2],
        "F02  Device feasible sets (constant-efficiency subset)\n" * subtitle;
        tellwidth = false,
    )
    ax = Axis(
        fig[1, 1],
        xlabel = "Electric output P_CHP [MW]",
        ylabel = "Heat output H_CHP [MW]",
        title = "CHP: fixed heat-to-power ratio",
    )
    lines!(ax, P, H; linewidth = 3, label = "Author approximation")
    scatter!(ax, s["P_CHP"], s["H_CHP"]; color = :tomato, label = "Saved dispatch")
    axislegend(ax; position = :lt)
    colsize!(fig.layout, 1, Relative(0.5))
    ax = Axis(
        fig[1, 2],
        xlabel = "Electric consumption [MW]",
        ylabel = "Heat production [MW]",
        title = "Electric boiler and heat pump",
    )
    for (name, col) in (("EB", :steelblue), ("HP", :teal))
        p = [0, dev["P_$(name)_max"]]
        lines!(ax, p, dev["COP_$name"] .* p; color = col, linewidth = 3, label = name)
        scatter!(ax, s["P_$name"], s["H_$name"]; color = col)
    end
    axislegend(ax; position = :lt)
    emit(fig, "F02-devices")
    CSV.write(joinpath(output, "F02-CHP.csv"), (P_MW = P, H_MW = H))
    CSV.write(
        joinpath(output, "F02-converters.csv"),
        [
            (device = name, P_MW = p, H_MW = dev["COP_$name"] * p) for name in ("EB", "HP") for
            p in (0, dev["P_$(name)_max"])
        ],
    )

    time_h = collect(1:T) .* Δt
    boundaries = collect(0:T) .* Δt
    fig = Figure(size = (1100, 820))
    Label(fig[0, 1:2], "F03  Heat transport, comfort and storage\n" * subtitle; tellwidth = false)
    ax = Axis(
        fig[1, 1],
        xlabel = "Interval end [h]",
        ylabel = "Temperature [K]",
        title = "Prescribed-flow pipe response",
    )
    for name in ("tau_S_in", "tau_S_out", "tau_R_in", "tau_R_out")
        scatterlines!(ax, time_h, s[name]; label = replace(name, "tau_" => ""))
    end
    axislegend(ax; position = :lb, labelsize = 11)
    ax = Axis(fig[1, 2], xlabel = "Time boundary [h]", ylabel = "Indoor temperature [K]")
    scatterlines!(ax, boundaries, s["tau_IN"]; color = :tomato)
    hlines!(
        ax,
        [d["building"]["tau_min"], d["building"]["tau_max"]];
        linestyle = :dash,
        color = :gray,
    )
    ax = Axis(
        fig[2, 1],
        xlabel = "Time boundary [h]",
        ylabel = "Stored energy [MWh]",
        title = "Horizon-wide modes; cyclic terminal energy",
    )
    for name in ("E_BS", "E_HS")
        scatterlines!(ax, boundaries, s[name]; label = name)
    end
    axislegend(ax; position = :rb)
    ax = Axis(
        fig[2, 2],
        xlabel = "Interval end [h]",
        ylabel = "Heat [MW]",
        title = "History contributes heat within the window",
    )
    source = s["H_CHP"] + s["H_HP"] + s["H_EB"] - s["H_HS_ch"] + s["H_HS_dis"]
    scatterlines!(ax, time_h, source; label = "Source")
    scatterlines!(ax, time_h, s["H_D"]; label = "Network load")
    axislegend(ax; position = :rt)
    colsize!(fig.layout, 1, Relative(0.5))
    emit(fig, "F03-trajectories")
    cp(joinpath(dir, "timeseries.csv"), joinpath(output, "F03-timeseries.csv"); force = true)
    cp(joinpath(dir, "states.csv"), joinpath(output, "F03-states.csv"); force = true)

    report = validate_r1_solution(saved.case, saved.result)
    ids = sort(unique(r.id for r in report.rows))
    maxima = [maximum(r.residual / r.tolerance for r in report.rows if r.id == id) for id in ids]
    fig = Figure(size = (1300, 800))
    Label(fig[0, 1], "F04  Independent residual / A1 tolerance\n" * subtitle; tellwidth = false)
    ax = Axis(
        fig[1, 1],
        width = 1140,
        height = 530,
        xlabel = "Constraint / bound ID",
        ylabel = "Residual / tolerance [1]",
        yscale = log10,
        xticks = (1:length(ids), ids),
        xticklabelrotation = pi / 2,
        xticklabelsize = 11,
    )
    barplot!(
        ax,
        1:length(ids),
        max.(maxima, 1e-12);
        fillto = 1e-12,
        color = [x <= 1 ? :steelblue : :tomato for x in maxima],
    )
    hlines!(ax, [1.0]; color = :red, linestyle = :dash)
    ylims!(ax, 1e-12, max(10.0, 10maximum(maxima)))
    emit(fig, "F04-residuals")
    CSV.write(joinpath(output, "F04-residuals.csv"), report.rows)
    CSV.write(joinpath(output, "F04-grouped.csv"), (id = ids, max_normalized = maxima))
    return output
end

if abspath(PROGRAM_FILE) == @__FILE__
    length(ARGS) in (1, 2) ||
        error("用法：julia --project=docs scripts/plot_r1.jl <运行目录> [新绘图目录]")
    output = length(ARGS) == 2 ? ARGS[2] : joinpath(ARGS[1], "figures")
    println(plot_r1_run(ARGS[1]; output))
end
