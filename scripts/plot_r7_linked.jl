using CSV, TOML, SHA, CairoMakie
length(ARGS)==2 || error("usage: plot_r7_linked.jl REPORT NEW_FIGURES")
src, out=abspath.(ARGS)
ispath(out)&&error("不覆盖详细状态规划图件")
hashfile(p) = bytes2hex(sha256(read(p)))
registry=TOML.parsefile(joinpath(src, "files.toml"))["files"]
sources=[
    "summary.csv",
    "iterations.csv",
    "events.csv",
    "normal-state.csv",
    "event-state.csv",
    "paired.csv",
    "rule.toml",
]
for p in sources
    hashfile(joinpath(src, p))==registry[p] || error("详细规划图源改变")
end
summary=collect(CSV.File(joinpath(src, "summary.csv")))
events=collect(CSV.File(joinpath(src, "events.csv")))
normal=collect(CSV.File(joinpath(src, "normal-state.csv")))
spatial=collect(CSV.File(joinpath(src, "event-state.csv")))
# 带失败空值的CSV列可能按字符串读取；只对已通过的数值行显式解析，不把空值变成零。
number(x) = x isa Real ? Float64(x) : parse(Float64, x)
groups=["original_hand", "reserve_zero", "reserve_heat_limit", "healthy_diagnostic"]
names=[
    "Original\nzero loss",
    "Reserve\nzero loss",
    "Reserve\nheat loss allowed",
    "Healthy internal line\nzero loss",
]
fig=Figure(size = (1440, 1050), fontsize = 17)
Label(
    fig[0, :],
    "F27 | Shared normal state and detailed recovery planning (synthetic)";
    fontsize = 23,
    tellwidth = false,
)
a=Axis(
    fig[1, 1];
    title = "A  Same declared flow domain: all-fault vs C&CG",
    xticks = (1:4, names),
    ylabel = "Expected normal cost (USD)",
)
for (j, method, color) in ((1, "extensive", :steelblue), (2, "finite_fault_ccg", :darkorange))
    for (i, g) in enumerate(groups)
        row=only(filter(r->r.group==g&&r.method==method&&r.solver=="HiGHS"&&r.substeps==4, summary))
        if row.model_pass
            scatter!(
                a,
                [i+(j==1 ? -0.09 : 0.09)],
                [number(row.cost_USD)];
                color,
                markersize = 13,
                marker = j==1 ? :circle : :diamond,
                label = i==3 ? (j==1 ? "All-fault master" : "Finite-fault C&CG") : nothing,
            )
            j==1&&text!(
                a,
                i,
                number(row.cost_USD)+4;
                text = string(round(number(row.cost_USD); digits = 3)),
                align = (:center, :bottom),
                fontsize = 15,
            )
        else
            row.status=="infeasible_certified" || error("图不能将未知状态改称不可行")
            j==1&&text!(
                a,
                i,
                195;
                text = "Infeasible\n(declared domain)",
                align = (:center, :center),
                color = :firebrick,
                fontsize = 15,
            )
        end
    end
end
ylims!(a, 175, 215)
xlims!(a, 0.5, 4.5)
b=Axis(
    fig[1, 2];
    title = "B  A shared normal battery trajectory",
    xlabel = "Normal time (h)",
    ylabel = "Battery energy (MWh)",
)
for (g, color) in (("reserve_heat_limit", :steelblue), ("healthy_diagnostic", :darkorange)),
    w in 1:2

    id=g*"_finite_fault_ccg_highs_n4"
    points=sort(
        filter(r->r.record==id&&r.quantity=="E_BES"&&r.scenario==w, normal);
        by = r->r.time_h,
    )
    length(points)==5 || error("正常电池轨迹不完整")
    lines!(
        b,
        getproperty.(points, :time_h),
        getproperty.(points, :value);
        color,
        linestyle = w==1 ? :solid : :dash,
        label = (g=="reserve_heat_limit" ? "Heat-loss allowance" : "Healthy line")*" / scenario $w",
    )
end
vlines!(b, [1, 2]; color = (:gray40, 0.6), linestyle = :dot)
ylims!(b, -0.04, 1.08)
c=Axis(
    fig[3, 1];
    title = "C  Final detailed fault checks (C&CG / HiGHS)",
    xlabel = "Event and internal-line fault",
    ylabel = "Expected unserved heat (MWh)",
)
labels=String[]
x=Ref(0)
for (g, color) in (("reserve_heat_limit", :steelblue), ("healthy_diagnostic", :darkorange))
    id=g*"_finite_fault_ccg_highs_n4"
    info=only(filter(r->r.record==id, summary))
    data=filter(r->r.record==id&&r.iteration==info.iterations&&r.kind=="fault_optimization", events)
    isempty(data)&&error("缺少最终详细故障检查")
    for r in data
        x[]+=1
        r.model_pass || error("图不能将失败热调度列为成功")
        push!(labels, (g=="reserve_heat_limit" ? "Reserve " : "Healthy ")*String(r.key))
        barplot!(c, [x[]], [number(r.heat_loss_MWh)]; color, width = 0.65)
        scatter!(c, [x[]], [number(r.heat_loss_MWh)]; color, markersize = 8)
        scatter!(c, [x[]], [number(r.limit_MWh)]; color = :black, marker = :hline, markersize = 24)
    end
end
c.xticks=(1:x[], labels)
c.xticklabelrotation=pi/6
ylims!(c, -0.015, 0.47)
d=Axis(
    fig[3, 2];
    title = "D  Inherited supply-pipe state from the same plan",
    xlabel = "Mass coordinate from inlet (tonnes)",
    ylabel = "Temperature (K)",
)
id="healthy_diagnostic_finite_fault_ccg_highs_n4"
last=only(filter(r->r.record==id, summary)).iterations
for (event, color) in ((1, :steelblue), (2, :darkorange))
    key="$event:0"
    data=sort(
        filter(
            r->r.record==id&&r.iteration==last&&r.key==key&&r.pipe==1&&r.side=="S"&&r.scenario==1,
            spatial,
        );
        by = r->r.segment,
    )
    isempty(data)&&error("缺少同一正常状态的空间见证")
    offset=0.0
    for (j, r) in enumerate(data)
        mass=collect(range(0, r.mass_kg; length = 32))
        temperature=r.base_K .+
                    r.amplitude_K .* exp.(r.rate_per_kg .* (r.from_left ? mass : r.mass_kg .- mass))
        lines!(
            d,
            (offset .+ mass) ./ 1000,
            temperature;
            color,
            linestyle = event==1 ? :solid : :dash,
            label = j==1 ? "Before event $event" : nothing,
        )
        offset+=r.mass_kg
    end
end
ylims!(d, 332, 354)
Legend(fig[2, 1], a; orientation = :horizontal, framevisible = false)
Legend(fig[2, 2], b; orientation = :horizontal, nbanks = 2, framevisible = false)
Legend(fig[4, 2], d; orientation = :horizontal, framevisible = false)
Label(
    fig[4, 1],
    "Black marks: allowed loss. A witness below the limit\nis not necessarily the minimum-loss recovery.";
    fontsize = 15,
    tellwidth = false,
)
Label(
    fig[5, :],
    "Prescribed normal and recovery flows; no AC / continuous-node / hydraulic certificate.\nAllowing all heat demand to be shed is not zero-loss resilience. Internal healthy-line control excludes line-failure certification.";
    fontsize = 15,
    tellwidth = false,
)
mkpath(out)
for p in sources
    cp(joinpath(src, p), joinpath(out, p))
end
save(joinpath(out, "F27-linked-planning.png"), fig; px_per_unit = 1.5)
save(joinpath(out, "F27-linked-planning.svg"), fig)
files=Dict(p=>hashfile(joinpath(out, p)) for p in readdir(out))
write(
    joinpath(out, "figure.toml"),
    sprint(
        io->TOML.print(
            io,
            Dict(
                "schema"=>"r7-linked-figure-v1",
                "origin"=>"synthetic",
                "solver_called"=>false,
                "run_ids"=>String.(getproperty.(summary, :run_id)),
                "report_manifest_sha256"=>hashfile(joinpath(src, "files.toml")),
                "source_sha256"=>hashfile(@__FILE__),
                "files"=>files,
                "settings"=>Dict(
                    "size_px"=>[1440, 1050],
                    "raster_scale"=>1.5,
                    "units"=>["USD", "MWh", "K", "h", "tonnes"],
                    "main_solver"=>"HiGHS",
                ),
            );
            sorted = true,
        ),
    ),
)
println("F27 drawn from saved original values only.")
