# F52/F53只读已核验图源；失败和缺失记录不画成零费用或零次迭代。
using CairoMakie, CSV, TOML, SHA
length(ARGS)==2 || error("usage: plot_r9_distributed.jl EVIDENCE NEW_FIGURES")
report, out=abspath.(ARGS)
ispath(out) && error("Do not overwrite figures")
meta=TOML.parsefile(joinpath(report, "evidence.toml"))
meta["schema"]=="r9-distributed-evidence-v1" || error("Evidence identity")
for (rel, h) in meta["derived_files"]
    bytes2hex(sha256(read(joinpath(report, rel))))==h || error("Figure source changed")
end
summary=collect(CSV.File(joinpath(report, "summary.csv")))
trajectory=collect(CSV.File(joinpath(report, "iterations.csv")))
quality_path=joinpath(report, "objective_reports.csv")
quality=isfile(quality_path) ? collect(CSV.File(quality_path)) : []
admm=filter(x->x.algorithm=="admm", summary)
fig=Figure(size = (1320, 230+330length(admm)), fontsize = 17)
Label(
    fig[0, 1:2],
    "F52 | Synthetic 44/38-node system | Actual distributed iterations",
    fontsize = 23,
)
for (i, s) in enumerate(admm)
    a=Axis(
        fig[i, 1],
        title = s.method,
        ylabel = "Residual / acceptance threshold",
        xlabel = "Completed iteration",
        yscale = log10,
    )
    b=Axis(
        fig[i, 2],
        title = "Resource cost; incomplete records are not ranked",
        ylabel = "CNY / day",
        xlabel = "Completed iteration",
    )
    rows=filter(x->x.method==s.method, trajectory)
    if isempty(rows)
        # 缺失轨迹没有数值坐标，不能让默认0…10刻度暗示已有迭代或费用。
        hidedecorations!(a; label = false)
        hidedecorations!(b; label = false)
        text!(
            a,
            0.5,
            0.5;
            space = :relative,
            text = s.record_pass ? "No completed iteration" :
                   "Record verification failed\nIteration count unknown",
            align = (:center, :center),
            color = :firebrick,
        )
        text!(
            b,
            0.5,
            0.5;
            space = :relative,
            text = s.mode_contract_pass ? string(s.status) :
                   "Fixed mode conflict\nNot an algorithm comparison",
            align = (:center, :center),
            color = :firebrick,
        )
        ylims!(a, 1e-4, 1e4)
    else
        hlines!(a, [1.0]; color = :black, linestyle = :dash)
        x=[r.iteration for r in rows]
        for (label, values, color) in (
            ("Primal / A4", [r.primal/1e-4 for r in rows], :steelblue),
            ("Dual / A4", [r.dual/1e-4 for r in rows], :darkorange),
            ("Merged model / A1", [r.model_ratio for r in rows], :firebrick),
        )
            lines!(a, x, max.(values, 1e-14); label, color)
        end
        axislegend(a; position = :rt, labelsize = 12)
        lines!(
            b,
            x,
            [r.cost_CNY for r in rows];
            color = :gray,
            linestyle = :dash,
            label = "Unaccepted aggregates included",
        )
        valid=filter(r->r.model_pass, rows)
        isempty(valid) || scatter!(
            b,
            [r.iteration for r in valid],
            [r.cost_CNY for r in valid];
            color = :steelblue,
            markersize = 7,
            label = "Model A1 passed",
        )
        peer=only(
            r for r in summary if r.algorithm=="central" && r.case==s.case && r.domain==s.domain
        )
        peer.model_candidate && hlines!(
            b,
            [peer.best_model_cost_CNY];
            color = :darkgreen,
            label = "Same-model central candidate",
        )
        axislegend(b; position = :rt, labelsize = 12)
    end
end
Label(
    fig[length(admm)+1, 1:2],
    "Run IDs are panel titles. Zero message initialization; fixed rho = 1. Log display floor only; original tests unchanged.",
    fontsize = 13,
)

statusfig=Figure(size = (1330, 1020), fontsize = 17)
Label(
    statusfig[0, 1],
    "F53 | Synthetic coordination | Accepted costs and evidence boundaries",
    fontsize = 23,
)
labels=[replace(s.method, "-"=>"\n") for s in summary]
a=Axis(
    statusfig[1, 1],
    ylabel = "Accepted model cost (CNY / day)",
    xticks = (1:length(summary), labels),
    xticklabelsize = 13,
)
valid=findall(s->s.model_candidate&&s.mode_contract_pass, summary)
if isempty(valid)
    text!(
        a,
        0.5,
        0.5;
        space = :relative,
        text = "No accepted model candidate",
        align = (:center, :center),
    )
else
    barplot!(a, valid, [summary[i].best_model_cost_CNY for i in valid]; color = :steelblue)
end
xlims!(a, 0.5, length(summary)+0.5)
b=Axis(
    statusfig[2, 1],
    title = "Flags: missing records remain unverified",
    xticks = (
        1:6,
        ["Mode contract", "Model A1", "Original grid", "Consensus A4", "ObjVal check", "Budget"],
    ),
    yticks = (1:length(summary), [s.method for s in summary]),
    yreversed = true,
    yticklabelsize = 12,
)
flags=zeros(6, length(summary))
for (i, s) in enumerate(summary)
    flags[:, i]=[
        s.mode_contract_pass,
        s.model_candidate,
        s.original_candidate,
        s.algorithm=="admm"&&s.consensus_A4_pass,
        -1,
        s.process_budget_pass,
    ]
    s.record_pass || (flags[2:4, i].=-1)
    s.algorithm=="central" && (flags[4, i]=-1)
    q=filter(x->x.method==s.method, quality)
    if length(q)==1 && !ismissing(only(q).reported_scalar_pass)
        flags[5, i]=Int(only(q).reported_scalar_pass)
    end
end
heatmap!(
    b,
    1:6,
    1:length(summary),
    flags;
    colormap = [:gray75, :tomato, :seagreen],
    colorrange = (-1, 1),
)
Label(
    statusfig[3, 1],
    "Green: checked pass. Red: not passed. Gray: unavailable or not applicable. Thermal checks cover steady energy/mass envelopes only.",
    fontsize = 13,
)
c=Axis(
    statusfig[4, 1],
    ylabel = "Complete process time (s)",
    xticks = (1:length(summary), labels),
    xticklabelsize = 13,
)
barplot!(c, 1:length(summary), [s.process_elapsed_sec for s in summary]; color = :slategray)
hlines!(c, [600.0]; color = :firebrick, linestyle = :dash)
Label(
    statusfig[5, 1],
    "No missing cost is replaced by zero. Solver bounds and candidate differences are separate. No bargaining or distributed speedup claim.",
    fontsize = 13,
)
mkpath(out)
save(joinpath(out, "F52-distributed-iterations.png"), fig)
save(joinpath(out, "F53-distributed-cost-status.png"), statusfig)
files=Dict{String,String}()
for name in ("F52-distributed-iterations.png", "F53-distributed-cost-status.png")
    files[name]=bytes2hex(sha256(read(joinpath(out, name))))
end
cp(@__FILE__, joinpath(out, "plot.jl"))
files["plot.jl"]=bytes2hex(sha256(read(joinpath(out, "plot.jl"))))
for name in ("summary.csv", "iterations.csv", "comparisons.csv")
    cp(joinpath(report, name), joinpath(out, name))
    files[name]=bytes2hex(sha256(read(joinpath(out, name))))
end
if isfile(quality_path)
    cp(quality_path, joinpath(out, "objective_reports.csv"))
    files["objective_reports.csv"]=bytes2hex(sha256(read(joinpath(out, "objective_reports.csv"))))
end
config=Dict(
    "schema"=>"r9-distributed-figure-v1",
    "origin"=>"synthetic",
    "input_manifest_sha256"=>meta["study_manifest_sha256"],
    "runs"=>[s.method for s in summary],
    "files"=>files,
    "optimization_performed"=>false,
    "log_display_floor"=>1e-14,
)
open(io->TOML.print(io, config; sorted = true), joinpath(out, "figure-config.toml"), "w")
