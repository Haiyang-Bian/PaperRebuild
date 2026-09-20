# 固定流量数值表示对照；冻结六项规则后顺序执行，不注入参考解或运行PG。
push!(LOAD_PATH, normpath(joinpath(@__DIR__, "..")))
using JuMP, Clarabel, Gurobi, TOML, SHA, Dates, UUIDs, CSV, Random
length(ARGS) == 2 || error("usage: probe_r9_fixed_scaling.jl STUDY NEW_DIRECTORY")
study, out = abspath(ARGS[1]), abspath(ARGS[2])
ispath(out) && error("Do not overwrite evidence")
root = normpath(joinpath(@__DIR__, ".."))
hashfile(p) = bytes2hex(sha256(read(p)))
toml(p, x) = open(io -> TOML.print(io, x; sorted = true), p, "w")
meta = TOML.parsefile(joinpath(study, "manifest.toml"))
mkpath(out)
files = Dict{String,String}()
science = [meta["science_files"]; "src/algorithms/r3_sensitivity.jl"]
for path in science
    source = path in meta["science_files"] ? joinpath(study, "frozen", path) : joinpath(root, path)
    target = joinpath(out, "code", path)
    mkpath(dirname(target))
    cp(source, target)
    files["code/"*path] = hashfile(target)
end
for (source, target) in (
    (joinpath(study, "case.toml"), "case.toml"),
    (joinpath(study, "runs/vf_vt/stage.toml"), "parent-stage.toml"),
    (@__FILE__, "probe-source.jl"),
    (joinpath(root, "Project.toml"), "root-project.toml"),
    (joinpath(root, "Manifest.toml"), "root-manifest.toml"),
    (joinpath(root, "tools/solvers/Project.toml"), "solver-project.toml"),
    (joinpath(root, "tools/solvers/Manifest.toml"), "solver-manifest.toml"),
)
    cp(source, joinpath(out, target))
    files[target] = hashfile(joinpath(out, target))
end
entries = [
    Dict("solver" => s, "representation" => v, "budget_sec" => 60.0) for
    s in ("Clarabel", "Gurobi") for v in ("raw", "objective_pow2", "rows_objective_pow2")
]
toml(
    joinpath(out, "manifest.toml"),
    Dict(
        "schema" => "r9-fixed-scaling-probe-v1",
        "files" => files,
        "science_files" => science,
        "entries" => entries,
        "gurobi_presolve" => 0,
        "uses_projected_gradient" => false,
        "parent_use" => "flow_parameter_only_no_primal_start",
        "julia_version" => string(VERSION),
    ),
)
mod = Module(gensym(:R9ScalingProbe))
Core.eval(mod, :(using JuMP, TOML, SHA, Dates, UUIDs, CSV, Random))
for path in science
    Base.include(mod, joinpath(out, "code", path))
end

# 2的整数幂精确缩放二进制浮点系数，不按结果选择系数或丢弃小项。
pow2scale(x) = exp2(ceil(log2(max(1.0, x))))
function scaled_model(c, flow, representation)
    b = Base.invokelatest(
        getfield(mod, :build_r9_flow_model),
        c;
        mode = :VF_VT,
        flow_schedule = flow,
    )
    costscale = 1.0
    if representation != "raw"
        d = c.data
        capacity =
            d["dt_h"]*sum(
                d["electric"]["grid_max_MW"]*abs(d["grid_price"][t]) +
                sum(abs(g["cost_per_MWh"])*g["P_max"] for g in d["devices"]) for t in 1:d["T"]
            )
        costscale = pow2scale(capacity)
        @objective(b.model, Min, b.cost_expression/costscale)
    end
    records = NamedTuple[]
    if representation == "rows_objective_pow2"
        for id in sort(collect(keys(b.constraints))), i in eachindex(b.constraints[id])
            cr = b.constraints[id][i]
            obj = constraint_object(cr)
            f, set = obj.func, obj.set
            fs = f isa AbstractVector ? f : [f]
            coefficients = [abs(a) for x in fs for (a, _) in linear_terms(x)]
            append!(coefficients, abs.(constant.(fs)))
            rhs =
                set isa MOI.EqualTo ? set.value :
                set isa MOI.LessThan ? set.upper : set isa MOI.GreaterThan ? set.lower : 0.0
            scale = pow2scale(max(maximum(coefficients; init = 1.0), abs(rhs)))
            factor = 1/scale
            newref = if set isa MOI.EqualTo
                @constraint(b.model, f*factor == rhs*factor)
            elseif set isa MOI.LessThan
                @constraint(b.model, f*factor <= rhs*factor)
            elseif set isa MOI.GreaterThan
                @constraint(b.model, f*factor >= rhs*factor)
            elseif set isa MOI.SecondOrderCone
                @constraint(b.model, factor .* f in SecondOrderCone())
            else
                error("Unexpected scale set")
            end
            delete(b.model, cr)
            b.constraints[id][i] = newref
            push!(records, (; formula = id, row = i, scale))
        end
    end
    return (;
        built = merge(
            b,
            (;
                objective_kind = representation == "raw" ? "operating_cost" :
                                 "operating_cost_divided_by_frozen_scale"
            ),
        ),
        costscale,
        records,
    )
end
Base.invokelatest() do
    c = getfield(mod, :load_r9_pv_case)(joinpath(out, "case.toml"))
    parent = TOML.parsefile(joinpath(out, "parent-stage.toml"))
    flow = permutedims(hcat(parent["values"]["m_pipe"]...))
    for entry in entries
        solver, representation = entry["solver"], entry["representation"]
        folder = joinpath(out, lowercase(solver)*"-"*representation)
        mkpath(folder)
        start = getfield(mod, :r3_clock)()
        built = Ref{Any}()
        optimizer =
            solver == "Clarabel" ? Clarabel.Optimizer :
            optimizer_with_attributes(Gurobi.Optimizer, "Presolve" => 0)
        try
            r = getfield(mod, :r3_solve)(
                c,
                () -> begin
                    built[] = scaled_model(c, flow, representation)
                    built[].built
                end,
                optimizer;
                budget_sec = 54,
                deadline = start+54,
            )
            r["objective_currency_scale"] = built[].costscale
            toml(joinpath(folder, "stage.toml"), r)
            isempty(built[].records) ||
                CSV.write(joinpath(folder, "row-scales.csv"), built[].records; newline = '\n')
            # 先显式恢复CNY目标语义，再调用原验证器；冻结旧失败不改写。
            currency = deepcopy(r)
            currency["original_scaled_solver_objective"] = get(r, "solver_objective", NaN)
            currency["objective_kind"] = "operating_cost"
            for key in ("solver_objective", "solver_bound", "raw_solver_bound")
                haskey(currency, key) && (currency[key] *= built[].costscale)
            end
            haskey(currency, "bound_objective_kind") &&
                (currency["bound_objective_kind"] = "operating_cost")
            v = getfield(mod, :validate_r3_solution)(c, currency)
            terminal = getfield(mod, :r9_flow_terminal_rows)(c, r)
            evidence = Dict{String,Any}(
                "status" => r["status"],
                "model_pass" => v.model_pass,
                "physical_pass" => v.physical_pass,
                "terminal_pass" => !isempty(terminal)&&all(x.pass for x in terminal),
                "objective_currency_scale" => built[].costscale,
            )
            CSV.write(joinpath(folder, "residuals.csv"), vcat(v.rows, terminal); newline = '\n')
            if haskey(r, "values")
                evidence["cost_CNY"] = r["operating_cost"]
                kkt = getfield(mod, :r3_kkt)(built[].built.model)
                toml(joinpath(folder, "kkt.toml"), kkt)
                evidence["kkt_trusted"] = representation=="raw" && kkt["trusted"]
                evidence["scaled_model_kkt_reported_trusted"] = kkt["trusted"]
                evidence["kkt_scope"] = "original_currency_only_for_raw_representation"
                evidence["kkt_reason"] = kkt["reason"]
                if v.model_pass
                    # 正常数目标换回CNY后才使用既有κ重构；保留原求解器目标及转换记录。
                    reconstructed = getfield(mod, :reconstruct_r3_pressure)(c, currency)
                    toml(joinpath(folder, "reconstructed.toml"), reconstructed)
                    rv = getfield(mod, :validate_r3_solution)(c, reconstructed)
                    evidence["reconstructed_physical_pass"] = rv.physical_pass
                end
            end
            evidence["elapsed_sec"] = getfield(mod, :r3_clock)()-start
            evidence["budget_pass"] = evidence["elapsed_sec"] <= entry["budget_sec"]
            toml(joinpath(folder, "evidence.toml"), evidence)
            println(solver, " ", representation, " ", evidence)
        catch err
            toml(
                joinpath(folder, "failure.toml"),
                Dict(
                    "error" => sprint(showerror, err),
                    "elapsed_sec" => getfield(mod, :r3_clock)()-start,
                ),
            )
            println(solver, " ", representation, " error: ", sprint(showerror, err))
        end
        flush(stdout)
    end
    all(hashfile(joinpath(out, p)) == h for (p, h) in files) || error("Frozen input changed")
end
