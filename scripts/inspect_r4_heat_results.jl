using CSV, TOML
length(ARGS) in (1, 2) || error("参数：热核查报告目录 [旧未分片残差CSV]")
dir=first(ARGS)
rows=collect(CSV.File(joinpath(dir, "comparison.csv")))
rr=vcat(
    [
        collect(CSV.File(joinpath(dir, "residuals-"*b*".csv"))) for
        b in ("reference10", "reference20")
    ]...,
)
intervals=collect(CSV.File(joinpath(dir, "mass-intervals.csv")))
nodes=collect(CSV.File(joinpath(dir, "node-intervals.csv")))
if length(ARGS)==2
    function row_counts(table)
        counts=Dict{Any,Int}()
        for row in table
            key=Tuple(getproperty(row, k) for k in propertynames(row))
            counts[key]=get(counts, key, 0)+1
        end
        counts
    end
    row_counts(rr)==row_counts(CSV.File(ARGS[2])) || error("残差分片丢失、增加或改变了原始行")
    println(
        "Lossless residual partition verified: ",
        length(rr),
        " rows, including duplicate multiplicity.",
    )
end
for band in unique(x.band for x in rows)
    free=filter(x->x.band==band&&x.stage=="free_mixing", rows)
    fixed=filter(x->x.band==band&&x.stage=="fixed_mixing", rows)
    println(
        band,
        ": free detailed ",
        count(x->x.pass, free),
        "/",
        length(free),
        "; joint electrical/thermal ",
        count(x->x.pass&&x.parent_electric_A1, free),
        "; fixed detailed ",
        count(x->x.pass, fixed),
    )
    for case in unique(x.case for x in rows)
        q=filter(x->x.case==case, free)
        println("  ", case, ": ", count(x->x.pass, q), "/", length(q))
    end
end
println(
    "maximum independent normalized residual among detailed passes = ",
    maximum(x.max_normalized_residual for x in rows if x.detailed_temperature_pass),
)
println(
    "maximum mass reconstruction change kg/s = ",
    maximum(x.max_mass_change_kg_s for x in rows if x.detailed_temperature_pass),
)
println(
    "mix temperature maximum K = ",
    maximum(x.residual for x in rr if startswith(x.equation, "mix_temperature")),
)
failed=filter(x->x.stage=="free_envelope"&&x.status=="solver_infeasible", rows)
certified=Set(x.run_id for x in intervals if x.materially_empty)
union!(certified, Set(x.run_id for x in nodes if x.materially_excludes_zero))
println(
    "free LP infeasible with direct interval contradiction = ",
    count(x->x.run_id in certified, failed),
    "/",
    length(failed),
)
println("negative example: open--electric--exact / reference20 / free_envelope")
full_power_A1=3e-6
full_mass_lower=(0.00126-full_power_A1)/(0.00418*40)
full_load_upper=full_power_A1/(0.00418*10)
println(
    "same example using full power A1: incoming lower=",
    full_mass_lower,
    " kg/s; load upper=",
    full_load_upper,
    " kg/s; remaining mismatch=",
    full_mass_lower-full_load_upper,
    " kg/s, versus mass A1 1.1e-5 kg/s",
)
for x in nodes
    x.parent=="open--electric--exact"&&x.band=="reference20" &&
    x.stage=="free_envelope"&&x.node==1&&x.t==1||continue
    println(x)
end
for x in intervals
    x.parent=="open--electric--exact"&&x.band=="reference20" &&
    x.stage=="free_envelope"&&x.t==1 &&
    ((x.kind=="pipe"&&x.entity==4)||(x.kind!="pipe"&&x.entity==1))||continue
    println(x)
end
