# 开发探针：冻结源码后运行；CF-CT原物理候选仅作直接参考的显式初值，不调用PG。
push!(LOAD_PATH, normpath(joinpath(@__DIR__, "..")))
using Gurobi, JuMP, TOML, SHA, Dates, UUIDs, CSV, Random
root = normpath(joinpath(@__DIR__, ".."))
length(ARGS) == 4 || error("usage: probe-r9-flow.jl NEW_DIRECTORY MODE PHYSICAL BUDGET_SECONDS")
out, mode = abspath(ARGS[1]), Symbol(ARGS[2])
physical, budget = parse(Bool, ARGS[3]), parse(Float64, ARGS[4])
mode in (:CF_CT, :CF_VT, :VF_CT, :VF_VT) || error("Unknown mode")
0 < budget <= 600 || error("Budget out of range")
ispath(out) && error("Do not overwrite probe")
parent = joinpath(root, "results/summaries/r9-numerics-20260921-v2")
hashfile(p) = bytes2hex(sha256(read(p)))
toml(path, x) = open(io -> TOML.print(io, x; sorted=true), path, "w")
science = [TOML.parsefile(joinpath(parent, "manifest.toml"))["science_files"];
    ["src/networks/r9_short_pipe.jl", "src/formulations/r9_flow.jl", "src/verification/r9_flow.jl"]]
mkpath(joinpath(out, "code"))
files = Dict{String,String}()
for path in [science; ["Project.toml", "Manifest.toml"]]
    target = joinpath(out, "code", path)
    mkpath(dirname(target))
    cp(joinpath(root, path), target)
    files["code/"*path] = hashfile(target)
end
for (source, target) in ((joinpath(parent, "case.toml"), "case.toml"),
    (joinpath(parent, "runs/cf_ct_gurobi_original/result.toml"), "cf-ct-witness.toml"),
    (@__FILE__, "probe-source.jl"))
    cp(source, joinpath(out, target))
    files[target] = hashfile(joinpath(out, target))
end
meta = Dict{String,Any}("schema"=>"r9-flow-development-probe-v1", "mode"=>string(mode),
    "physical_model"=>physical, "budget_sec"=>budget, "files"=>files,
    "science_files"=>science, "started_utc"=>string(now(UTC)),
    "initialization"=>"declared_CF_CT_original_grid_candidate_for_direct_reference_only",
    "terminal_interpretation"=>"literal", "uses_projected_gradient"=>false,
    "parent_manifest_sha256"=>hashfile(joinpath(parent, "manifest.toml")))
toml(joinpath(out, "manifest.toml"), meta)
mod = Module(gensym(:R9FlowProbe))
Core.eval(mod, :(using JuMP, TOML, SHA, Dates, UUIDs, CSV, Random))
for path in science
    Base.include(mod, joinpath(out, "code", path))
end

function set_witness(c, b, saved)
    point = Dict{VariableRef,Float64}()
    for (key, array) in b.variables
        (startswith(key, "alpha_") || startswith(key, "beta_")) && continue
        vals = key == "r9_inverse_relative" ?
            [first(c.data["heat"]["pipes"][p]["fixed_flow"])/saved["m_pipe"][p][t]
                for p in axes(array, 1), t in axes(array, 2)] :
            ndims(array) == 1 ? saved[key] : permutedims(hcat(saved[key]...))
        for i in eachindex(array)
            array[i] isa VariableRef && (point[array[i]] = vals[i])
        end
    end
    for _ in 1:3
        before = length(point)
        for cr in all_constraints(b.model, AffExpr, MOI.EqualTo{Float64})
            obj = constraint_object(cr)
            unknown = [(a, x) for (a, x) in linear_terms(obj.func) if !haskey(point, x) && a != 0]
            length(unknown) == 1 || continue
            a, x = only(unknown)
            known = constant(obj.func) + sum(k*point[y] for (k, y) in linear_terms(obj.func)
                if haskey(point, y); init=0.0)
            point[x] = (obj.set.value-known)/a
        end
        length(point) == before && break
    end
    Set(keys(point)) == Set(all_variables(b.model)) || error("Incomplete initial witness")
    for (x, v) in point
        set_start_value(x, v)
    end
    return b
end

Base.invokelatest() do
    c = getfield(mod, :load_r9_pv_case)(joinpath(out, "case.toml"))
    witness = TOML.parsefile(joinpath(out, "cf-ct-witness.toml"))["stage"]["values"]
    start = getfield(mod, :r3_clock)()
    r = getfield(mod, :r3_solve)(c,
        () -> set_witness(c, getfield(mod, :build_r9_flow_model)(c; mode, physical), witness),
        Gurobi.Optimizer; budget_sec=0.9budget, deadline=start+0.9budget)
    toml(joinpath(out, "stage.toml"), r)
    validation = getfield(mod, :validate_r3_solution)(c, r)
    terminal = getfield(mod, :r9_flow_terminal_rows)(c, r)
    evidence = Dict{String,Any}("status"=>r["status"], "model_pass"=>validation.model_pass,
        "physical_pass"=>validation.physical_pass,
        "terminal_pass"=>!isempty(terminal) && all(x.pass for x in terminal))
    CSV.write(joinpath(out, "residuals.csv"), vcat(validation.rows, terminal))
    if haskey(r, "values")
        heat = getfield(mod, :r9_daily_heat_balance)(c, r["values"])
        evidence["daily_heat"] = Dict(string(k)=>getproperty(heat, k) for k in keys(heat))
        evidence["cost_CNY"] = r["operating_cost"]
        evidence["bound_CNY"] = get(r, "solver_bound", "unavailable")
    end
    evidence["elapsed_sec"] = getfield(mod, :r3_clock)()-start
    evidence["budget_pass"] = evidence["elapsed_sec"] <= budget+0.1
    for (path, hash) in files
        hashfile(joinpath(out, path)) == hash || error("Frozen file changed: $path")
    end
    toml(joinpath(out, "evidence.toml"), evidence)
    println(evidence)
end
