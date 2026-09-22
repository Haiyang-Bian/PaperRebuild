include("r3_setup.jl")
using CSV
length(ARGS)==1 || error("usage: compare_r3_baseline.jl STUDY_TOML")
file=only(ARGS)
study=TOML.parsefile(file)
rows=filter(x->x["method"]=="baseline", study["runs"])
groups=Tuple{Symbol,Vector{String}}[]
for name in ("single-source", "two-source")
    for group in ("initialization", "boundary")
        choices=filter(x->x["case_group"]==name && x["group"]==group, rows)
        key=group=="initialization" ? "initial_label" : "boundary"
        for label in unique(x[key] for x in choices)
            push!(groups, (:geometry, [x["id"] for x in choices if x[key]==label]))
        end
    end
    for geometry in ("physical_euclidean", "normalized_euclidean")
        for (factor, group) in ((:initialization, "initialization"), (:boundary, "boundary"))
            push!(
                groups,
                (
                    factor,
                    [
                        x["id"] for x in rows if
                        x["case_group"]==name && x["geometry"]==geometry && x["group"]==group
                    ],
                ),
            )
        end
    end
    push!(
        groups,
        (
            :step,
            [
                x["id"] for x in rows if x["case_group"]==name &&
                    x["initial_label"]=="schpd" &&
                    x["geometry"]=="physical_euclidean" &&
                    x["group"] in ("initialization", "step")
            ],
        ),
    )
end
evidence=Dict{String,Any}[]
for (factor, ids) in groups
    length(ids)>=2 || continue
    println("PAIR ", factor, " ", join(ids, ","))
    flush(stdout)
    loaded=[
        read_r3_run(
            normpath(joinpath(dirname(file), only(x["directory"] for x in rows if x["id"]==id))),
        ) for id in ids
    ]
    compare_r3_baselines(loaded; factor)
    push!(evidence, Dict("factor"=>string(factor), "ids"=>ids, "pass"=>true))
    GC.gc()
end
output=joinpath(dirname(file), "pairing-"*string(uuid4())[1:8]*".toml")
open(output, "w") do io
    TOML.print(
        io,
        Dict("study_sha256"=>bytes2hex(sha256(read(file))), "groups"=>evidence);
        sorted = true,
    )
end
println("Verified ", length(evidence), " declared-factor groups: ", output)
