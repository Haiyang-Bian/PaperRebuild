# 仅从保存数值绘图；不申请Gurobi许可，不重新优化。
include("r4_setup.jl")
using CairoMakie, CSV
import PaperRebuild: plot_r4_run

function plot_r4_run(
    path::AbstractString;
    output = joinpath("results", "runs", "r4-figures", basename(path)),
)
    saved=read_r4_run(path)
    r=saved.result
    c=saved.case
    haskey(r, "values") || error("该运行无数值解；使用comparison.csv展示失败状态，不画虚构调度")
    ispath(output) && error("不覆盖已有图，请指定新目录")
    mkpath(output)
    s=r["values"]
    T=c.data["T"]
    dt=c.data["dt_h"]
    t=collect(1:T) .* dt
    header="Synthetic R4 | "*r["run_id"]
    set_theme!(Theme(font = "DejaVu Sans", fontsize = 15))
    rows=r["validation"]["rows"]
    scopes=["model", "electric_original", "heat", "ledger"]
    maxima=[
        maximum([x["residual"]/x["tolerance"] for x in rows if x["scope"]==scope]; init = 0.0) for
        scope in scopes
    ]
    f=Figure(size = (1000, 440))
    Label(f[0, 1], header, fontsize = 16, tellwidth = false)
    colsize!(f.layout, 1, Relative(1.0))
    ax=Axis(
        f[1, 1],
        title = "F04  Independent residuals",
        ylabel = "Max residual / A1 tolerance",
        yscale = log10,
        xticks = (1:4, ["Model", "Electric\noriginal", "Heat energy\nflow", "Ledger"]),
    )
    barplot!(
        ax,
        1:4,
        max.(maxima, 1e-12),
        color = [:steelblue, :orange, :seagreen, :purple],
        fillto = 1e-12,
    )
    hlines!(ax, [1.0], color = :red, linestyle = :dash, label = "A1 threshold")
    axislegend(ax; position = :rt)
    save(joinpath(output, "F04.png"), f)
    CSV.write(
        joinpath(output, "F04.csv"),
        [(scope = scopes[i], ratio = maxima[i], threshold = 1.0) for i in 1:4],
    )
    dispatch=NamedTuple[]
    for k in 1:T
        push!(
            dispatch,
            (
                t_h = t[k],
                CHP = sum(s["P_CHP"][i][k] for i in 1:3),
                PV = sum(s["P_PV"][i][k] for i in 1:3),
                grid = s["P_grid"][k],
                HP = sum(s["P_HP"][i][k] for i in 1:3),
                EB = sum(s["P_EB"][i][k] for i in 1:3),
                charge = s["P_ch"][2][k],
                discharge = s["P_dis"][2][k],
                energy = s["E"][2][k+1],
                Pload = sum(s["P_D"][i][k] for i in 1:3),
                Hload = sum(s["H_D"][i][k] for i in 1:3),
            ),
        )
    end
    contracts=r["ledger"]["contracts"]
    q(carrier) = [
        only(
            x["peer_export_MW"] for
            x in contracts if x["actor"]=="A"&&x["carrier"]==carrier&&x["t"]==k
        ) for k in 1:T
    ]
    f=Figure(size = (1200, 920))
    Label(f[0, 1:2], header, fontsize = 16)
    ax=Axis(f[1, 1], title = "F10  Electric supply", xlabel = "Time (h)", ylabel = "MW")
    for (key, label) in ((:CHP, "CHP"), (:PV, "PV"), (:grid, "External grid"))
        lines!(ax, t, getproperty.(dispatch, key), label = label)
    end
    axislegend(ax; position = :lt)
    ax=Axis(f[1, 2], title = "Power-to-heat and load", xlabel = "Time (h)", ylabel = "MW")
    for (key, label) in (
        (:HP, "HP electric"),
        (:EB, "EB electric"),
        (:Pload, "Electric demand"),
        (:Hload, "Heat demand"),
    )
        lines!(ax, t, getproperty.(dispatch, key), label = label)
    end
    axislegend(ax; position = :rt)
    ax=Axis(
        f[2, 1],
        title = "Bilateral contracts: A -> B positive",
        xlabel = "Time (h)",
        ylabel = "MW",
    )
    lines!(ax, t, q("P"), label = "Electricity")
    lines!(ax, t, q("H"), label = "Heat")
    axislegend(ax; position = :rt)
    ax=Axis(
        f[2, 2],
        title = "Electric branch loading",
        xlabel = "Time (h)",
        ylabel = "|P| / capacity",
    )
    for p in 1:2
        lines!(
            ax,
            t,
            abs.(s["P_branch"][p]) .* c.data["electric"]["S_base_MVA"] ./
            c.data["electric"]["edges"][p]["P_max"],
            label = "Branch "*string(p),
        )
    end
    hlines!(ax, [1.0], color = :red, linestyle = :dash)
    axislegend(ax; position = :rt)
    ax=Axis(
        f[3, 1],
        title = "Heat pipe loading",
        xlabel = "Time (h)",
        ylabel = "H inlet / capacity",
    )
    for p in 1:2
        lines!(
            ax,
            t,
            s["H_in"][p] ./ c.data["heat"]["pipes"][p]["H_max"],
            label = "Pipe "*string(p),
        )
    end
    hlines!(ax, [1.0], color = :red, linestyle = :dash)
    axislegend(ax; position = :rt)
    ax=Axis(f[3, 2], title = "Battery state", xlabel = "Time (h)", ylabel = "MWh")
    lines!(ax, vcat(0.0, t), s["E"][2], label = "Energy")
    axislegend(ax; position = :rt)
    save(joinpath(output, "F10.png"), f)
    CSV.write(joinpath(output, "F10-dispatch.csv"), dispatch)
    CSV.write(
        joinpath(output, "F10-contracts.csv"),
        [
            NamedTuple{Tuple(Symbol.(sort(collect(keys(x)))))}(
                Tuple(x[k] for k in sort(collect(keys(x)))),
            ) for x in contracts
        ],
    )
    network=[
        (
            t_h = t[k],
            branch = p,
            P_MW = s["P_branch"][p][k]*c.data["electric"]["S_base_MVA"],
            P_capacity = c.data["electric"]["edges"][p]["P_max"],
            H_in_MW = s["H_in"][p][k],
            H_out_MW = s["H_out"][p][k],
            H_capacity = c.data["heat"]["pipes"][p]["H_max"],
        ) for k in 1:T for p in 1:2
    ]
    CSV.write(joinpath(output, "F10-network.csv"), network)
    alt=deepcopy(c.data["settlement"])
    alt["P_peer"]=150.0
    alt["H_peer"]=110.0
    alternate=r4_ledger(c, s; settlement = alt, p2p_enabled = r["ledger"]["p2p_enabled"])
    money=r["ledger"]["actors"]
    ids=[x["actor"] for x in money]
    f=Figure(size = (1150, 500))
    Label(f[0, 1:2], header*" | No bargaining", fontsize = 16)
    ax=Axis(
        f[1, 1],
        title = "F12  Resource costs before payments",
        ylabel = "Synthetic USD",
        xticks = (1:3, ids),
    )
    for (j, key) in enumerate(("resource", "dissatisfaction", "external"))
        barplot!(ax, (1:3) .+ (j-2)*0.23, [x[key] for x in money], width = 0.22, label = key)
    end
    axislegend(ax; position = :rt)
    ax=Axis(
        f[1, 2],
        title = "Example utility after settlement",
        ylabel = "Synthetic USD",
        xticks = (1:3, ids),
    )
    barplot!(
        ax,
        (1:3) .- 0.15,
        [x["utility"] for x in money],
        width = 0.28,
        label = "Teaching price",
    )
    barplot!(
        ax,
        (1:3) .+ 0.15,
        [x["utility"] for x in alternate["actors"]],
        width = 0.28,
        label = "Alternative peer price",
    )
    hlines!(ax, [0.0], color = :black)
    axislegend(ax; position = :lb)
    save(joinpath(output, "F12.png"), f)
    CSV.write(
        joinpath(output, "F12.csv"),
        [
            (
                actor = ids[i],
                resource = money[i]["resource"],
                dissatisfaction = money[i]["dissatisfaction"],
                external = money[i]["external"],
                cash = money[i]["internal_net_cash"],
                utility = money[i]["utility"],
                alternative_utility = alternate["actors"][i]["utility"],
            ) for i in 1:3
        ],
    )
    config=Dict(
        "run_id"=>r["run_id"],
        "input_sha256"=>c.sha256,
        "origin"=>"synthetic",
        "bargaining"=>"not_performed",
        "script_sha256"=>bytes2hex(sha256(read(@__FILE__))),
        "units"=>c.data["units"],
        "residual_floor_for_log"=>1e-12,
        "initial_battery_MWh"=>s["E"][2][1],
        "alternative_settlement"=>alt,
    )
    write(joinpath(output, "figure-config.toml"), PaperRebuild.r4_text(config))
    println("R4 figures: ", abspath(output))
    return abspath(output)
end

if abspath(PROGRAM_FILE)==@__FILE__
    length(ARGS) in (1, 2) || error("参数：运行目录 [新图表目录]")
    length(ARGS)==1 ? plot_r4_run(ARGS[1]) : plot_r4_run(ARGS[1]; output = ARGS[2])
end
