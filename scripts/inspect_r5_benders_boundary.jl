using PaperRebuild, TOML, SHA

length(ARGS) == 1 || error("参数：已有边界审计目录；只读，不重新求解")
dir = abspath(only(ARGS))
r = TOML.parsefile(joinpath(dir, "result.toml"))
# 开发反例也按原源码解释；不能用当前修正后的矩阵悄悄重算旧记录。
for (rel, hash) in r["source_hashes_at_solve"]
    path=joinpath(dir, "code", split(rel, '/')...)
    bytes2hex(sha256(read(path)))==hash||error("反例源码变化：$rel")
end
snapshot=Module(:R5BoundarySnapshot)
Core.eval(snapshot, :(using JuMP, TOML, SHA, Dates, UUIDs))
files=["src/networks/fixed_flow_heat.jl"]
for name in ("market", "dispatch"),
    layer in ("core", "formulations", "verification", "algorithms", "reporting")

    push!(files, "src/$layer/r5_$name.jl")
end
append!(files, ["src/verification/r5_dispatch_duality.jl", "src/formulations/r5_dispatch_dual.jl"])
for name in ("commitment", "risk", "benders"),
    layer in ("core", "formulations", "verification", "algorithms", "reporting")

    rel="src/$layer/r5_$name.jl"
    haskey(r["source_hashes_at_solve"], rel)&&push!(files, rel)
end
for rel in files
    Base.include(snapshot, joinpath(dir, "code", split(rel, '/')...))
end
c = snapshot.load_r5_risk_case(joinpath(dir, "case.toml"))
R = PaperRebuild.r5_benders_rational
println("status=", r["status"], " input=", c.sha256)
for step in r["iterations"]
    println("iteration ", step["iteration"], " first stage=", step["master"]["first_stage"])
    for (name, id) in step["diagnostic_source_ids"]
        src = r["subproblems"][id]
        sys = snapshot.r5_benders_system(
            c,
            src["scenario"],
            src["first_stage"],
            src["branch"];
            elastic = true,
        )
        x = snapshot.r5_benders_flat(src["first_stage"])
        y = src["flat_values"]
        errors = Tuple{Float64,String,Float64,Float64}[]
        for (key, row) in sys.rows
            slack =
                sum(R(a)*R(y[k]) for (k, a) in row.coefficients; init = R(0)) - R(row.rhs) -
                sum(R(a)*R(x[k]) for (k, a) in row.parameters; init = R(0))
            violation =
                row.sense == :eq ? abs(slack) : row.sense == :ge ? max(0, -slack) : max(0, slack)
            push!(errors, (Float64(violation), key, Float64(slack), src["raw_duals"][key]))
        end
        sort!(errors; by = first, rev = true)
        println("  scenario=", name, " objective=", src["solver_objective"])
        println("  largest exact encoded row violations (violation,id,slack,dual):")
        foreach(println, Iterators.take(errors, 10))
        println("  elastic values:")
        foreach(
            println,
            sort!([(k, v) for (k, v) in y if startswith(k, "elastic/") && abs(v)>1e-14]),
        )
        println("  heat values:")
        foreach(
            println,
            sort!([(k, v) for (k, v) in y if startswith(k, "τ_") || startswith(k, "H_")]),
        )
    end
    for id in step["new_cut_ids"]
        q = r["cuts"][id]
        q["kind"] == "feasibility" || continue
        println("  cut ", q["scenario"], " constant=", q["constant"], " gradient=", q["gradient"])
    end
end
