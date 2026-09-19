using CairoMakie, CSV, TOML, SHA
# 绘图环境保持独立；冻结科学模块从根环境读取已有JuMP依赖，不安装新包。
push!(LOAD_PATH, normpath(joinpath(@__DIR__, "..")))
include("r7_normal_evidence.jl")

function plot_r7_normal(args)
    length(args)==2 || error("plot_r7_normal.jl EVIDENCE NEW_OUTPUT")
    bundle, dest=args
    ispath(dest)&&error("不覆盖旧科学图")
    x=r7_normal_evidence(["check", bundle])
    normal=collect(CSV.File(joinpath(bundle, "normal-trajectory.csv")))
    events=collect(CSV.File(joinpath(bundle, "event-summary.csv")))
    d=x.normal.case.data
    dt=d["dt_h"]
    T=d["periods"]
    fig=Figure(size = (1180, 850), fontsize = 15)
    Label(
        fig[0, 1:2],
        "R7 | Prescribed-flow normal plan and inherited-state recovery",
        fontsize = 21,
    )
    a=Axis(
        fig[1, 1],
        xlabel = "Normal hour",
        ylabel = "Electrical power (MW)",
        title = "A. Saved normal dispatch (scenario 1)",
    )
    rows=filter(r->r.scenario==1, normal)
    times=[(r.t-0.5)*dt for r in rows]
    for (key, label, color) in (
        (:P_PCC_MW, "PCC import", :steelblue),
        (:P_CHP_MW, "CHP", :darkorange),
        (:P_dis_MW, "Battery discharge", :seagreen),
        (:P_ch_MW, "Battery charge", :purple),
    )
        lines!(a, times, [getproperty(r, key) for r in rows]; label, color, linewidth = 2)
        scatter!(a, times, [getproperty(r, key) for r in rows]; color, markersize = 5)
    end
    axislegend(a; position = :rt, labelsize = 12)
    b=Axis(
        fig[1, 2],
        xlabel = "Normal time boundary (h)",
        ylabel = "Relative heat / battery energy (MWh)",
        title = "B. Inventory from original state trajectories",
    )
    for (startkey, endkey, label, color) in (
        (:E_S_start_MWh, :E_S_end_MWh, "Supply pipe", :firebrick),
        (:E_R_start_MWh, :E_R_end_MWh, "Return pipe", :steelblue),
        (:E_BES_start_MWh, :E_BES_end_MWh, "Battery, scenario 1", :seagreen),
    )
        values=vcat(getproperty(first(rows), startkey), [getproperty(r, endkey) for r in rows])
        lines!(b, collect(0:T) .* dt, values; label, color, linewidth = 2)
    end
    rows2=filter(r->r.scenario==2, normal)
    if !isempty(rows2)
        values=vcat(first(rows2).E_BES_start_MWh, [r.E_BES_end_MWh for r in rows2])
        lines!(
            b,
            collect(0:T) .* dt,
            values;
            label = "Battery, scenario 2",
            color = :seagreen,
            linestyle = :dash,
            linewidth = 2,
        )
    end
    vlines!(
        b,
        [(x.event_case.data["event_start"]-1)*dt];
        color = :black,
        linestyle = :dot,
        label = "Event starts",
    )
    axislegend(b; position = :rt, labelsize = 11)
    c=Axis(
        fig[2, 1],
        title = "C. Frozen electrical network",
        limits = (-0.4, d["electric"]["nodes"]+0.4, -1.1, 1.1),
    )
    hidedecorations!(c)
    hidespines!(c)
    for line in d["electric"]["lines"]
        i, j=line["from"], line["to"]
        lines!(c, [Float64(i), Float64(j)], [0.0, 0.0]; color = :gray, linewidth = 3)
        text!(
            c,
            (i+j)/2,
            0.20;
            text = line["vulnerable"] ? "vulnerable line" : "line",
            align = (:center, :bottom),
            fontsize = 12,
        )
    end
    for node in 1:d["electric"]["nodes"]
        scatter!(c, [Float64(node)], [0.0]; color = :steelblue, markersize = 25)
        devices=join([g["kind"] for g in d["devices"] if g["electric_node"]==node], " + ")
        text!(c, node, -0.22; text = "Node $node\n$devices", align = (:center, :top), fontsize = 12)
    end
    text!(
        c,
        (1+d["electric"]["nodes"])/2,
        0.72;
        text = "PCC is disconnected in both event cases",
        align = (:center, :center),
        fontsize = 13,
    )
    e=Axis(
        fig[2, 2],
        xlabel = "Internal line fault",
        ylabel = "Expected unserved energy (MWh)",
        title = "D. Recovery of the same normal plan",
        xticks = (collect(1:length(events)), [string(r.fault) for r in events]),
    )
    ymax=max(
        0.25,
        maximum([ismissing(r.loss_MWh) ? 0.0 : Float64(r.loss_MWh) for r in events]; init = 0.0)*1.7,
    )
    ylims!(e, 0, ymax)
    xlims!(e, 0.5, length(events)+0.5)
    for (i, r) in enumerate(events)
        if r.model_pass && !ismissing(r.loss_MWh)
            barplot!(
                e,
                [i],
                [Float64(r.loss_electric_MWh)];
                color = :steelblue,
                width = 0.5,
                label = i==1 ? "Electrical" : nothing,
            )
            # 热失供条以累计高度绘制，避免将其单独数值误作堆叠终点。
            if r.loss_heat_MWh>0
                barplot!(
                    e,
                    [i],
                    [Float64(r.loss_MWh)];
                    fillto = [Float64(r.loss_electric_MWh)],
                    color = :darkorange,
                    width = 0.5,
                )
            end
            text!(
                e,
                i,
                Float64(r.loss_MWh)+0.04ymax;
                text = string(round(r.loss_MWh; digits = 6)),
                align = (:center, :bottom),
                fontsize = 12,
            )
        else
            message=r.status=="infeasible_certified" ?
                    "No feasible\nrecovery\n(certified infeasible)" : "No candidate\n$(r.status)"
            text!(
                e,
                i,
                0.45ymax;
                text = message,
                align = (:center, :center),
                color = :firebrick,
                fontsize = 14,
            )
        end
    end
    Label(
        fig[3, 1:2],
        "Synthetic development case | Normal cost: $(round(x.normal.validation["cost_USD"];digits=4)) USD | No complete preplan or C&CG claim\nNormal run: $(x.normal.result["run_id"])",
        fontsize = 12,
        tellwidth = false,
    )
    rowgap!(fig.layout, 18)
    colgap!(fig.layout, 28)
    mkpath(dest)
    for file in ("normal-trajectory.csv", "event-summary.csv")
        cp(joinpath(bundle, file), joinpath(dest, file))
    end
    save(joinpath(dest, "F20-normal-event.png"), fig; px_per_unit = 1.5)
    save(joinpath(dest, "F20-normal-event.svg"), fig)
    config=Dict(
        "schema"=>"r7-normal-event-figure-v1",
        "origin"=>d["origin"],
        "normal_run_id"=>x.normal.result["run_id"],
        "event_run_ids"=>[r.result["run_id"] for r in x.runs],
        "plot_script_sha256"=>bytes2hex(sha256(read(@__FILE__))),
        "evidence_manifest_sha256"=>bytes2hex(
            sha256(read(joinpath(bundle, "evidence-files.toml"))),
        ),
        "scope"=>"conditional_normal_plan_and_given_fault_recovery_development",
        "units"=>["h", "MW", "MWh", "USD"],
    )
    open(joinpath(dest, "figure.toml"), "w") do io
        TOML.print(io, config; sorted = true)
    end
    files=Dict(f=>bytes2hex(sha256(read(joinpath(dest, f)))) for f in readdir(dest))
    open(joinpath(dest, "files.toml"), "w") do io
        TOML.print(io, Dict("files"=>files); sorted = true)
    end
    println("F20 normal/event figure saved from frozen values; no optimization")
end

abspath(PROGRAM_FILE)==(@__FILE__) && plot_r7_normal(ARGS)
