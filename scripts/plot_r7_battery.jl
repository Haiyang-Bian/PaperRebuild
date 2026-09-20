using CSV, TOML, SHA, CairoMakie
length(ARGS)==2 || error("usage: plot_r7_battery.jl PUBLIC_REPORT NEW_FIGURES")
src, out=abspath.(ARGS)
ispath(out)&&error("不覆盖电池图件")
hashfile(p) = bytes2hex(sha256(read(p)))
registry=TOML.parsefile(joinpath(src, "files.toml"))["files"]
sources=["summary.csv", "domain-pairs.csv", "ideal-cycles.csv", "rule.toml"]
for p in sources
    hashfile(joinpath(src, p))==registry[p] || error("电池图源改变")
end
summary=collect(CSV.File(joinpath(src, "summary.csv")))
pairs=collect(CSV.File(joinpath(src, "domain-pairs.csv")))
cycles=collect(CSV.File(joinpath(src, "ideal-cycles.csv")))
groups=["hand", "reserve_event_1", "reserve_event_2"]
names=["Hand", "Reserve 1", "Reserve 2"]
fig=Figure(size = (1440, 650), fontsize = 18)
Label(
    fig[0, :],
    "F26 | Battery domain audit at prescribed flow (synthetic)",
    fontsize = 24,
    tellwidth = false,
)
a=Axis(
    fig[1, 1],
    title = "A  Original values and explicit ideal-battery reconstruction",
    xticks = (1:3, names),
    ylabel = "Maximum simultaneous cycle (MW)",
)
before=[
    maximum(r.cycle_removed_MW for r in cycles if startswith(r.record, g*"_reference")) for
    g in groups
]
after=zeros(3)
all(r.energy_increment_MWh==0 && r.other_values_preserved for r in cycles) ||
    error("原值重构未保持状态")
barplot!(a, (1:3) .- 0.17, before; width = 0.28, color = :darkorange, label = "Original candidate")
scatter!(
    a,
    (1:3) .+ 0.17,
    after;
    markersize = 13,
    color = :steelblue,
    label = "Reconstructed candidate",
)
for i in 1:3
    text!(
        a,
        i-0.17,
        before[i]+0.007;
        text = string(round(before[i]; digits = 6)),
        align = (:center, :bottom),
        fontsize = 15,
    )
end
ylims!(a, -0.01, 0.25)
b=Axis(
    fig[1, 2],
    title = "B  Healthy-line redispatch: changing only battery domain",
    xticks = (1:6, [name*"\n"*flow for name in names for flow in ("Inherited", "Reference")]),
    ylabel = "Electricity + heat unserved (MWh)",
)
selected=[
    only(filter(r->r.record==g*"_"*f*"_fault0_highs_n16", pairs)) for g in groups for
    f in ("parent", "reference")
]
all(r.parent_model_pass && r.new_model_pass && r.battery_rule_only_changed for r in selected) ||
    error("非同输入合格对照")
for (offset, field, color, label) in (
    (-0.16, :parent_loss_MWh, :gray50, "Original sum bound"),
    (0.16, :new_loss_MWh, :steelblue, "Explicit exclusivity"),
)
    values=[getproperty(r, field) for r in selected]
    barplot!(b, (1:6) .+ offset, values; width = 0.27, color, label)
    scatter!(b, (1:6) .+ offset, values; markersize = 7, color)
end
ylims!(b, -0.002, 0.054)
Legend(fig[2, 1], a; orientation = :horizontal, framevisible = false)
Legend(fig[2, 2], b; orientation = :horizontal, framevisible = false)
Label(
    fig[3, :],
    "All original states retained. Ideal efficiencies = 1; no AC/hydraulic or free-flow certificate.\n12 positive-flow disconnected-line runs remain conditionally infeasible (not plotted as zero loss).",
    fontsize = 16,
    tellwidth = false,
)
mkpath(out)
for p in sources
    cp(joinpath(src, p), joinpath(out, p))
end
save(joinpath(out, "F26-battery-domain.png"), fig; px_per_unit = 1.5)
save(joinpath(out, "F26-battery-domain.svg"), fig)
files=Dict(p=>hashfile(joinpath(out, p)) for p in readdir(out))
write(
    joinpath(out, "figure.toml"),
    sprint(
        io->TOML.print(
            io,
            Dict(
                "schema"=>"r7-battery-figure-v1",
                "origin"=>"synthetic",
                "solver_called"=>false,
                "run_ids"=>String.(getproperty.(summary, :run_id)),
                "report_manifest_sha256"=>hashfile(joinpath(src, "files.toml")),
                "source_sha256"=>hashfile(@__FILE__),
                "files"=>files,
                "settings"=>Dict(
                    "size_px"=>[1440, 650],
                    "raster_scale"=>1.5,
                    "units"=>["MW", "MWh"],
                    "main_solver"=>"HiGHS",
                ),
            );
            sorted = true,
        ),
    ),
)
println("F26 drawn from saved raw-value tables only.")
