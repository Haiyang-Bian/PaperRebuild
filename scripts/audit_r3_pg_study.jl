using TOML
length(ARGS)==1 || error("usage: audit_r3_pg_study.jl STUDY_TOML")
root=dirname(abspath(only(ARGS)))
matrix(x) = reduce(vcat, permutedims.(x))
for (name, other) in (("single-source", "single-no-halfspace"), ("two-source", "two-no-halfspace"))
    a=TOML.parsefile(joinpath(root, name*"-schpd", "run.toml"))
    b=TOML.parsefile(joinpath(root, other, "run.toml"))
    println(
        name,
        " ablation initial max kg/s difference = ",
        maximum(abs, matrix(a["initial_flow"])-matrix(b["initial_flow"])),
    )
    fixed=TOML.parsefile(joinpath(root, name*"-case_fixed", "run.toml"))
    box=TOML.parsefile(joinpath(root, name*"-box50", "run.toml"))
    println(
        name,
        " fixed vs box50 initial max kg/s difference = ",
        maximum(abs, matrix(fixed["initial_flow"])-matrix(box["initial_flow"])),
    )
end
for name in ("single-impossible-heat", "single-delay-switch")
    r=TOML.parsefile(joinpath(root, name, "run.toml"))
    lastrow=last(r["iterations"])
    st=r["stages"][lastrow["stage"]]
    println(
        name,
        " final mode=",
        lastrow["mode"],
        " merit=",
        lastrow["merit"],
        " trials=",
        length(lastrow["trials"]),
    )
    v=st["values"]
    slacks=[
        (
            equation = x["equation"],
            entity = x["entity"],
            t = x["t"],
            unit = x["unit"],
            signed_value = x["scale"]*(v["elastic_positive"][i]-v["elastic_negative"][i]),
        ) for (i, x) in enumerate(st["elastic_rows"])
    ]
    println(sort(slacks; by = x->-abs(x.signed_value))[1:5])
end
