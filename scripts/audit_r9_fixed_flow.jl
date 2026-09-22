# 固定流量代入审计：仅使用已保存原值，不求解、不生成PG初值、不修正控制量。
push!(LOAD_PATH, normpath(joinpath(@__DIR__, "..")))
using JuMP, TOML, SHA, Dates, UUIDs, CSV, Random

length(ARGS) == 3 || error("usage: audit_r9_fixed_flow.jl STUDY PARENT_MODE NEW_AUDIT")
study, mode, out = abspath(ARGS[1]), Symbol(ARGS[2]), abspath(ARGS[3])
mode in (:CF_CT, :VF_CT, :VF_VT) || error("This audit requires a saved accepted parent")
ispath(out) && error("Do not overwrite evidence")
hashfile(p) = bytes2hex(sha256(read(p)))
toml(path, x) = open(io -> TOML.print(io, x; sorted = true), path, "w")
meta = TOML.parsefile(joinpath(study, "manifest.toml"))
mkpath(out)
files = Dict{String,String}()
for (source, target) in (
    (joinpath(study, "case.toml"), "case.toml"),
    (joinpath(study, "runs", lowercase(string(mode)), "stage.toml"), "parent-stage.toml"),
    (@__FILE__, "audit-source.jl"),
)
    cp(source, joinpath(out, target))
    files[target] = hashfile(joinpath(out, target))
end
for path in meta["science_files"]
    target = joinpath(out, "code", path)
    mkpath(dirname(target))
    cp(joinpath(study, "frozen", path), target)
    files["code/"*path] = hashfile(target)
end
mod = Module(gensym(:R9FixedWitness))
Core.eval(mod, :(using JuMP, TOML, SHA, Dates, UUIDs, CSV, Random))
for path in meta["science_files"]
    Base.include(mod, joinpath(out, "code", path))
end
Base.invokelatest() do
    c = getfield(mod, :load_r9_pv_case)(joinpath(out, "case.toml"))
    parent = TOML.parsefile(joinpath(out, "parent-stage.toml"))
    vals = parent["values"]
    flow = permutedims(hcat(vals["m_pipe"]...))
    b = getfield(mod, :build_r9_flow_model)(c; mode, flow_schedule = flow)
    point = Dict{VariableRef,Float64}()
    for (key, array) in b.variables
        x = ndims(array) == 1 ? vals[key] : permutedims(hcat(vals[key]...))
        size(array) == size(x) || error("Shape differs for $key")
        for i in eachindex(array)
            array[i] isa VariableRef || continue
            haskey(point, array[i]) && point[array[i]] != x[i] && error("Conflicting variable")
            point[array[i]] = x[i]
        end
    end
    original = copy(point)
    auxiliary = NamedTuple[]
    for _ in 1:10
        before = length(point)
        for cr in all_constraints(b.model, AffExpr, MOI.EqualTo{Float64})
            obj = constraint_object(cr)
            unknown = [(a, v) for (a, v) in linear_terms(obj.func) if a != 0 && !haskey(point, v)]
            length(unknown) == 1 || continue
            a, v = only(unknown)
            known =
                constant(obj.func) +
                sum(k*point[w] for (k, w) in linear_terms(obj.func) if haskey(point, w); init = 0.0)
            point[v] = (obj.set.value-known)/a
            push!(auxiliary, (; variable = string(v), value = point[v], equation = string(cr)))
        end
        length(point) == before && break
    end
    Set(keys(point)) == Set(all_variables(b.model)) || error("Incomplete witness")
    all(point[v] == x for (v, x) in original) || error("Original controls changed")
    all(isfinite, values(point)) || error("Nonfinite witness")
    labels = Dict(cr => id for (id, refs) in b.constraints for cr in refs)
    distances = primal_feasibility_report(b.model, point; atol = 0.0)
    rows = [
        (; formula = get(labels, cr, "variable_bound"), constraint = string(cr), residual = r)
        for (cr, r) in distances
    ]
    sort!(rows; by = x -> (-x.residual, x.formula, x.constraint))
    CSV.write(joinpath(out, "constraint-distances.csv"), rows; newline = '\n')
    isempty(auxiliary) || CSV.write(joinpath(out, "auxiliary.csv"), auxiliary; newline = '\n')
    constants = NamedTuple[]
    for (key, array) in b.variables
        x = ndims(array) == 1 ? vals[key] : permutedims(hcat(vals[key]...))
        for i in eachindex(array)
            array[i] isa Number || continue
            push!(constants, (; key, index = string(i), residual = abs(array[i]-x[i])))
        end
    end
    CSV.write(joinpath(out, "substituted-values.csv"), constants; newline = '\n')
    result = Dict{String,Any}(
        "schema" => "r9-fixed-flow-witness-audit-v1",
        "mode" => string(mode),
        "class" => b.class,
        "input_sha256" => c.sha256,
        "flow_sha256" => getfield(mod, :r2_flow_hash)(flow),
        "parent_cost_CNY" => parent["operating_cost"],
        "rebuilt_cost_CNY" => value(v -> point[v], objective_function(b.model)),
        "variables" => length(point),
        "auxiliary_count" => length(auxiliary),
        "constraint_count" =>
            num_constraints(b.model; count_variable_in_set_constraints = true),
        "maximum_raw_distance" => maximum(values(distances); init = 0.0),
        "maximum_substitution_difference" => maximum(x.residual for x in constants; init = 0.0),
        "controls_unchanged" => true,
        "solver_run" => false,
        "uses_projected_gradient" => false,
        "source_manifest_sha256" => hashfile(joinpath(study, "manifest.toml")),
        "files" => files,
    )
    result["output_files"] = Dict(
        p => hashfile(joinpath(out, p)) for
        p in readdir(out) if isfile(joinpath(out, p)) && !haskey(files, p)
    )
    toml(joinpath(out, "audit.toml"), result)
    println(
        "Fixed-flow witness: ",
        mode,
        " max distance=",
        result["maximum_raw_distance"],
        "; substitution=",
        result["maximum_substitution_difference"],
    )
    for row in first(rows, min(8, length(rows)))
        println(row.formula, " ", row.residual)
    end
end
