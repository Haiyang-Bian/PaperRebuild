using PaperRebuild, TOML, CSV, SHA, Dates, UUIDs, CairoMakie
include("plot_r3_pg.jl")
include("plot_r3_comparison.jl")
length(ARGS)==1 || error("usage: report_r3_v2.jl STUDY_TOML")
studyfile=abspath(only(ARGS));
study=TOML.parsefile(studyfile)
root=normpath(joinpath(@__DIR__, ".."))
id=study["batch"]*"-"*string(uuid4())[1:8]
dest=joinpath(root, "results", "summaries", "r3-v2", id);
mkpath(dest)
cp(studyfile, joinpath(dest, "study.toml"))
for file in ("frozen.toml", "config.toml")
    cp(joinpath(dirname(studyfile), file), joinpath(dest, file))
end
function csvdict(path, rows)
    isempty(rows) && return
    keysall=sort!(unique(vcat([collect(keys(r)) for r in rows]...)))
    CSV.write(path, [(; (Symbol(k)=>get(r, k, missing) for k in keysall)...) for r in rows])
end
summaries=Dict{String,Any}[];
modes=Dict{String,Any}[];
inventory=Dict{String,Any}[]
starts=Dict{String,Vector{Matrix{Float64}}}()
for e in study["runs"]
    println("REPORT ", e["id"])
    flush(stdout)
    dir=joinpath(dirname(studyfile), e["directory"])
    loaded=read_r3_run(dir)
    r=loaded.result
    c=loaded.case
    final=r["final_stage"]>0 ? r["stages"][r["final_stage"]] : nothing
    row=Dict{String,Any}(
        "id"=>e["id"],
        "group"=>e["group"],
        "case"=>e["case"],
        "run_id"=>basename(dirname(abspath(dir)))*"/"*loaded.metadata["run_id"],
        "input_sha256"=>c.sha256,
        "physical_pass"=>loaded.validation.physical_pass,
        "outer_status"=>r["outer_status"],
        "outer_converged"=>r["outer_converged"],
        "cost_optimization_complete"=>r["cost_optimization_complete"],
        "optional_bound_failures"=>count(s->haskey(s, "bound_error"), r["stages"]),
        "elapsed_sec"=>r["elapsed_sec"],
        "iterations"=>length(get(r, "iterations", Any[])),
        "local_trials"=>sum(
            count(t->t["kind"]=="primal_local_model", x["trials"]) for
            x in get(r, "iterations", Any[]);
            init = 0,
        ),
        "local_accepted"=>sum(
            count(t->t["kind"]=="primal_local_model" && t["accepted"], x["trials"]) for
            x in get(r, "iterations", Any[]);
            init = 0,
        ),
    )
    !isnothing(final) && (row["cost"]=final["operating_cost"])
    if isnothing(final)
        k=findlast(s->s["stage"]=="pressure_reconstruction", r["stages"])
        isnothing(k) && (k=findlast(s->haskey(s, "values"), r["stages"]))
        if !isnothing(k)
            residuals=filter(x->x.scope=="physics", loaded.validation.stages[k].rows)
            if !isempty(residuals)
                worst=residuals[argmax(x.residual/x.tolerance for x in residuals)]
                row["failure_stage"]=k
                row["worst_physics_equation"]=worst.equation
                row["worst_physics_residual"]=worst.residual
                row["worst_physics_tolerance"]=worst.tolerance
                row["worst_physics_unit"]=worst.unit
            end
        end
    end
    if e["group"]=="robustness"
        old=read_r3_run(joinpath(root, e["old_directory"]))
        row["v1_physical_pass"]=old.validation.physical_pass
        row["v1_outer_status"]=old.result["outer_status"]
        row["v1_elapsed_sec"]=old.result["elapsed_sec"]
        row["v1_outer_converged"]=old.result["outer_converged"]
        row["same_initial_flow"]=old.result["initial_flow_sha256"]==r["initial_flow_sha256"]
        if e["id"] in [e["case"]*"-"*s for s in ("schpd", "case_fixed", "box25", "box50", "box75")]
            m=PaperRebuild.r3_matrix(r["initial_flow"])
            group=get!(starts, e["case"], Matrix{Float64}[])
            tolerance=[1e-6+1e-6*p["flow_max"] for p in c.data["heat"]["pipes"]]
            matched=findfirst(x->all(abs.(x-m) .<= tolerance), group)
            if isnothing(matched)
                push!(group, m)
                matched=length(group)
            end
            row["initial_group_A1"]=matched
        end
        if old.result["final_stage"]>0
            row["v1_cost"]=old.result["stages"][old.result["final_stage"]]["operating_cost"]
            !isnothing(final) && (row["cost_change_v2_minus_v1"]=row["cost"]-row["v1_cost"])
        end
    end
    push!(summaries, row)
    # 原始运行仍在忽略目录；公开摘要保留哈希和所有图源，不复制大规模对偶轨迹。
    push!(
        inventory,
        Dict(
            "id"=>e["id"],
            "run_sha256"=>bytes2hex(sha256(read(joinpath(dir, "run.toml")))),
            "source_hashes"=>loaded.metadata["source_hashes"],
            "input_sha256"=>c.sha256,
        ),
    )
    plot_r3_pg_run(dir; output = joinpath(dest, e["id"]), loaded)
    if e["group"]=="robustness"
        plot_r3_pg_comparison(old.result, r, e["id"], joinpath(dest, e["id"]))
    end
end
statistics=Dict{String,Any}[]
middle(xs) =
    isodd(length(xs)) ? sort(xs)[(length(xs)+1)÷2] :
    sum(sort(xs)[(length(xs)÷2):(length(xs)÷2+1)])/2
for name in sort!(collect(keys(starts))), version in ("v1", "v2")
    rows=filter(r->r["case"]==name && haskey(r, "initial_group_A1"), summaries)
    prefix=version=="v1" ? "v1_" : ""
    valid=filter(r->r[prefix*"physical_pass"], rows)
    stat=Dict{String,Any}(
        "case"=>name,
        "version"=>version,
        "initial_count"=>length(rows),
        "distinct_initial_groups_A1"=>length(starts[name]),
        "physical_pass_count"=>length(valid),
        "physical_pass_rate"=>length(valid)/length(rows),
        "numeric_stop_count"=>count(r->r[prefix*"outer_converged"], rows),
    )
    for (field, values) in (
        ("cost", [r[prefix*"cost"] for r in valid]),
        ("elapsed_sec", [r[prefix*"elapsed_sec"] for r in rows]),
    )
        isempty(values) && continue
        stat[field*"_best"]=minimum(values)
        stat[field*"_median"]=middle(values)
        stat[field*"_worst"]=maximum(values)
    end
    push!(statistics, stat)
end
csvdict(joinpath(dest, "five-initial-statistics.csv"), statistics)
for name in unique(e["case"] for e in study["runs"] if e["group"]=="modes")
    println("COMPARE ", name)
    flush(stdout)
    entries=filter(e->e["group"]=="modes" && e["case"]==name, study["runs"])
    dirs=[joinpath(dirname(studyfile), e["directory"]) for e in entries]
    rows=compare_r3_modes(dirs)
    for r in rows
        r["case"]=name
    end
    append!(modes, rows)
    valid=filter(r->r["physical_pass"], rows)
    fig=Figure(size = (1350, 700), fontsize = 14)
    Label(fig[0, 1:2], "Synthetic four modes | "*name*" | core + common recovery tail")
    labels=[
        replace(r["mode"], "_"=>"-")*"\n"*(occursin("reference", r["method"]) ? "reference" : "PG")
        for r in valid
    ]
    x=collect(eachindex(valid))
    ax=Axis(
        fig[1, 1];
        xticks = (x, labels),
        ylabel = "Cost (currency)",
        title = "Verified cycle cost",
    )
    if !isempty(valid)
        barplot!(ax, x, [r["core_cost"] for r in valid]; label = "core", color = :steelblue)
        barplot!(
            ax,
            x,
            [r["total_cost"] for r in valid];
            fillto = [r["core_cost"] for r in valid],
            label = "recovery",
            color = :orange,
        )
        axislegend(ax)
    end
    ax2=Axis(
        fig[1, 2];
        xticks = (x, labels),
        ylabel = "PV energy (MWh)",
        title = "Use and curtailment",
    )
    if !isempty(valid)
        barplot!(ax2, x, [r["pv_used_MWh"] for r in valid]; label = "used", color = :seagreen)
        barplot!(
            ax2,
            x,
            [r["pv_available_MWh"] for r in valid];
            fillto = [r["pv_used_MWh"] for r in valid],
            label = "curtailed",
            color = :gray,
        )
        axislegend(ax2)
    end
    Label(
        fig[2, 1:2],
        "Only independently verified physical + recovered terminal states are plotted. Missing candidates stay in CSV.",
        fontsize = 13,
    )
    save(joinpath(dest, name*"-F08-modes.png"), fig)
    save(joinpath(dest, name*"-F08-modes.svg"), fig)
    timeseries=NamedTuple[]
    fig=Figure(size = (1350, 1000), fontsize = 14)
    Label(fig[0, 1:2], "Synthetic dispatch and thermal balance | "*name)
    axes=[Axis(fig[i, j]; xlabel = "Time (h)") for i in 1:2, j in 1:2]
    axes[1, 1].ylabel="CHP power (MW)"
    axes[1, 2].ylabel="PV power (MW)"
    axes[2, 1].ylabel="Source heat (MW)"
    axes[2, 2].ylabel="Cumulative net thermal balance (MWh)"
    for (entry, dir) in zip(entries, dirs)
        l=read_r3_run(dir)
        r=l.result
        c=l.case
        r["final_stage"]>0 || continue
        v=r["stages"][r["final_stage"]]["values"]
        d=c.data
        h=d["heat"]
        series=NamedTuple[]
        energy=0.0
        for t in 1:d["T"]
            chp=sum(
                v["P_device"][g][t] for
                g in eachindex(d["devices"]) if d["devices"][g]["kind"]=="CHP"
            )
            pv=sum(
                v["P_device"][g][t] for
                g in eachindex(d["devices"]) if d["devices"][g]["kind"]=="PV"
            )
            heat=sum(
                v["H_port"][j][t] for j in eachindex(h["nodes"]) if h["nodes"][j]["role"]=="source"
            )
            demand=sum(n["H_MW"][t] for n in h["nodes"])
            loss=sum(
                h["cp_J_kgK"]/1e6*v["m_pipe"][p][t]*(
                    PaperRebuild.r3_mass_replay(c, v, p, t, side).star-v["tau_"*side*"_out"][p][t]
                ) for p in eachindex(h["pipes"]), side in ("S", "R")
            )
            energy+=d["dt_h"]*(heat-demand-loss)
            push!(
                series,
                (
                    run_id = basename(dirname(abspath(dir)))*"/"*entry["id"],
                    mode = entry["mode"],
                    method = entry["method"],
                    time_h = t*d["dt_h"],
                    recovery = t>4,
                    chp_MW = chp,
                    pv_MW = pv,
                    source_heat_MW = heat,
                    heat_loss_MW = loss,
                    net_heat_MWh = energy,
                ),
            )
        end
        append!(timeseries, series)
        for (ax, field) in (
            (axes[1, 1], :chp_MW),
            (axes[1, 2], :pv_MW),
            (axes[2, 1], :source_heat_MW),
            (axes[2, 2], :net_heat_MWh),
        )
            lines!(
                ax,
                [s.time_h for s in series],
                [getproperty(s, field) for s in series];
                label = entry["mode"]*" "*entry["method"],
            )
        end
    end
    for ax in axes
        vlines!(ax, [4.0]; color = :black, linestyle = :dash)
    end
    Legend(fig[3, 1:2], axes[1, 1]; orientation = :horizontal, nbanks = 2, labelsize = 11)
    Label(
        fig[4, 1:2],
        "Dashed line: recovery begins. Net heat is integrated source - load - replay loss, not a reconstructed exact pipe temperature field.",
        fontsize = 12,
    )
    save(joinpath(dest, name*"-F09-dispatch.png"), fig)
    CSV.write(joinpath(dest, name*"-F09-source.csv"), timeseries)
end
csvdict(joinpath(dest, "comparison.csv"), summaries)
csvdict(joinpath(dest, "modes.csv"), modes)
open(
    io->TOML.print(io, Dict("runs"=>inventory); sorted = true),
    joinpath(dest, "evidence-hashes.toml"),
    "w",
)
open(
    io->TOML.print(
        io,
        Dict(
            "origin"=>"synthetic",
            "batch"=>study["batch"],
            "renderer"=>"CairoMakie",
            "reoptimized"=>false,
            "script_sha256"=>bytes2hex(sha256(read(@__FILE__))),
            "source"=>"saved R3 evidence",
            "figures"=>["F04", "F05", "F06", "F08", "F09"],
        );
        sorted = true,
    ),
    joinpath(dest, "figure-config.toml"),
    "w",
)
println(dest)
