# 开发探针：冻结源码后运行；CF-CT原物理候选仅作直接参考的显式初值，不调用PG。
push!(LOAD_PATH, normpath(joinpath(@__DIR__, "..")))
using Gurobi, JuMP, TOML, SHA, Dates, UUIDs, CSV, Random
root = normpath(joinpath(@__DIR__, ".."))
length(ARGS) in (4, 5) || error("usage: probe-r9-flow.jl NEW_DIRECTORY MODE PHYSICAL BUDGET_SECONDS [global|local]")
out, mode = abspath(ARGS[1]), Symbol(ARGS[2])
physical, budget = parse(Bool, ARGS[3]), parse(Float64, ARGS[4])
policy = length(ARGS) == 5 ? ARGS[5] : "global"
policy in ("global", "local") || error("Unknown solver policy")
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
    "solver_policy"=>policy,
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
    raw = primal_feasibility_report(b.model, point; atol=0.0)
    return (; b, point, raw)
end

Base.invokelatest() do
    c = getfield(mod, :load_r9_pv_case)(joinpath(out, "case.toml"))
    witness = TOML.parsefile(joinpath(out, "cf-ct-witness.toml"))["stage"]["values"]
    start = getfield(mod, :r3_clock)()
    if policy == "global"
        initial = Ref{Any}()
        r = getfield(mod, :r3_solve)(c,
            () -> begin
                initial[] = set_witness(c, getfield(mod, :build_r9_flow_model)(c; mode, physical), witness)
                initial[].b
            end,
            Gurobi.Optimizer; budget_sec=0.9budget, deadline=start+0.9budget)
        r["initial_max_raw_violation"] = maximum(values(initial[].raw); init=0.0)
    else
        initial = set_witness(c, getfield(mod, :build_r9_flow_model)(c; mode, physical), witness)
        b, point = initial.b, initial.point
        r = getfield(mod, :r3_solve)(c, () -> b, nothing; budget_sec=budget,
            deadline=start+0.9budget)
        set_optimizer(b.model, Gurobi.Optimizer)
        for (key, val) in ("Threads"=>1, "Seed"=>0, "NonConvex"=>2,
            "FeasibilityTol"=>1e-9, "OptimalityTol"=>1e-9, "OptimalityTarget"=>1,
            "NLBarPFeasTol"=>1e-9, "NLBarDFeasTol"=>1e-9,
            "LogToConsole"=>0, "LogFile"=>joinpath(out, "solver-local.log"))
            set_optimizer_attribute(b.model, key, val)
        end
        # 原生PStart须在全部变量/约束复制后赋值；Start用于全局MIP路径。
        MOI.Utilities.attach_optimizer(backend(b.model))
        for (x, val) in point
            MOI.set(backend(b.model), Gurobi.VariableAttribute("PStart"), index(x), val)
        end
        r["initial_max_raw_violation"] = maximum(values(initial.raw); init=0.0)
        r["initial_vector_count"] = length(point)
        r["solver_policy"] = "local_NL_barrier_OptimalityTarget_1"
        r["warm_start_attribute"] = "PStart"
        remaining = start+0.9budget-getfield(mod, :r3_clock)()
        r["build_sec"] = getfield(mod, :r3_clock)()-start
        if remaining <= 0
            r["status"] = "time_limit_no_solution"
        else
            set_time_limit_sec(b.model, remaining)
            optimize!(b.model)
            term, primal = string(termination_status(b.model)), string(primal_status(b.model))
            has_solution = has_values(b.model) && primal_status(b.model) == MOI.FEASIBLE_POINT
            r["status"] = getfield(mod, :r2_status)([Dict("termination"=>term,"primal"=>primal)],
                1, has_solution, term=="TIME_LIMIT")
            r["termination"], r["primal"] = term, primal
            r["solver"] = solver_name(b.model)
            r["solver_version"] = MOI.get(backend(b.model), MOI.SolverVersion())
            r["bound_status"] = "not_available_for_local_optimization"
            if has_solution
                r["values"] = Dict(k=>getfield(mod, :r2_extract)(a) for (k,a) in b.variables)
                r["solver_objective"] = objective_value(b.model)
                r["operating_cost"] = getfield(mod, :r3_operating_cost)(c, r["values"])
                r["objective"] = r["operating_cost"]
            end
        end
        r["elapsed_sec"] = getfield(mod, :r3_clock)()-start
    end
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
