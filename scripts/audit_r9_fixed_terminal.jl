# 给定流量下提取全部终端仿射方程；不锚定参考解、不删小系数、不运行优化。
push!(LOAD_PATH, normpath(joinpath(@__DIR__, "..")))
using JuMP, TOML, SHA, Dates, UUIDs, CSV, Random
length(ARGS) == 2 || error("usage: audit_r9_fixed_terminal.jl STUDY NEW_AUDIT")
study, out = abspath.(ARGS)
ispath(out) && error("Do not overwrite evidence")
root = normpath(joinpath(@__DIR__, ".."))
hashfile(p) = bytes2hex(sha256(read(p)))
toml(p, x) = open(io -> TOML.print(io, x; sorted = true), p, "w")
parent = TOML.parsefile(joinpath(study, "manifest.toml"))
mkpath(out)
files = Dict{String,String}()
for path in parent["science_files"]
    target = joinpath(out, "code", path)
    mkpath(dirname(target))
    # 仅前向接口增量，其他科学块逐字节复用父批次。
    source =
        path == "src/formulations/r9_reduced.jl" ? joinpath(root, path) :
        joinpath(study, "frozen", path)
    cp(source, target)
    files["code/"*path] = hashfile(target)
end
for (source, target) in (
    (joinpath(study, "case.toml"), "case.toml"),
    (joinpath(study, "runs/vf_vt/stage.toml"), "parent-stage.toml"),
    (@__FILE__, "audit-source.jl"),
)
    cp(source, joinpath(out, target))
    files[target] = hashfile(joinpath(out, target))
end
mod = Module(gensym(:R9TerminalAudit))
Core.eval(mod, :(using JuMP, TOML, SHA, Dates, UUIDs, CSV, Random))
for path in parent["science_files"]
    Base.include(mod, joinpath(out, "code", path))
end
Base.invokelatest() do
    c = getfield(mod, :load_r9_pv_case)(joinpath(out, "case.toml"))
    saved = TOML.parsefile(joinpath(out, "parent-stage.toml"))["values"]
    flow = permutedims(hcat(saved["m_pipe"]...))
    b = getfield(mod, :build_r9_reduced_model)(c; mode = :VF_VT, flow_schedule = flow)
    coordinates = [
        (j, t) for (j, n) in enumerate(c.data["heat"]["nodes"]) if n["role"]=="source" for
        t in 1:c.data["T"]
    ]
    sourcevars = [
        only(x for (a, x) in linear_terms(b.variables["tau_S_port"][j, t]) if a != 0) for
        (j, t) in coordinates
    ]
    refs = get(b.constraints, "R9-P6", Any[])
    A = [coefficient(constraint_object(cr).func, x) for cr in refs, x in sourcevars]
    rhs = [constraint_object(cr).set.value-constant(constraint_object(cr).func) for cr in refs]
    Set(x for cr in refs for (a, x) in linear_terms(constraint_object(cr).func) if a != 0) ⊆
    Set(sourcevars) || error("Unaccounted terminal variables")
    x = [saved["tau_S_port"][j][t]-b.temperature_centre_K for (j, t) in coordinates]
    point = Dict(sourcevars .=> x)
    for key in ("P_device", "H_device", "P_grid", "Q_grid", "P_branch", "Q_branch", "v", "ell")
        a = b.variables[key]
        v = ndims(a)==1 ? saved[key] : permutedims(hcat(saved[key]...))
        for i in eachindex(a)
            point[a[i]] = v[i]
        end
    end
    Set(keys(point))==Set(all_variables(b.model)) || error("Incomplete reduced witness")
    distances = primal_feasibility_report(b.model, point; atol = 0.0)
    thermal = [key for key in keys(b.variables) if startswith(key, "tau_") || key=="H_port"]
    max_difference = maximum(
        abs(value(v->point[v], a[i])-permutedims(hcat(saved[key]...))[i]) for key in thermal for
        a in (b.variables[key],) for i in eachindex(a)
    )
    CSV.write(
        joinpath(out, "terminal-matrix.csv"),
        [(row = i, column = j, coefficient = A[i, j]) for i in axes(A, 1) for j in axes(A, 2)];
        newline = '\n',
    )
    CSV.write(
        joinpath(out, "terminal-rhs.csv"),
        [(row = i, rhs = rhs[i]) for i in eachindex(rhs)];
        newline = '\n',
    )
    CSV.write(
        joinpath(out, "source-temperatures.csv"),
        [
            (column = i, node = j, t, value_K = saved["tau_S_port"][j][t], relative_K = x[i]) for
            (i, (j, t)) in enumerate(coordinates)
        ];
        newline = '\n',
    )
    CSV.write(
        joinpath(out, "terminal-witness-residuals.csv"),
        [(row = i, residual = abs(sum(A[i, :] .* x)-rhs[i])) for i in eachindex(rhs)];
        newline = '\n',
    )
    CSV.write(joinpath(out, "constant-checks.csv"), b.constant_checks; newline = '\n')
    report=Dict{String,Any}(
        "schema"=>"r9-fixed-terminal-system-v1",
        "files"=>files,
        "rows"=>size(A, 1),
        "columns"=>size(A, 2),
        "input_sha256"=>c.sha256,
        "flow_sha256"=>getfield(mod, :r2_flow_hash)(flow),
        "class"=>b.class,
        "solver_run"=>false,
        "maximum_forward_thermal_difference"=>max_difference,
        "maximum_raw_distance"=>maximum(values(distances); init = 0.0),
        "maximum_terminal_witness_residual_K"=>maximum(abs, A*x-rhs),
        "rebuilt_cost_CNY"=>value(v->point[v], objective_function(b.model)),
        "science_files"=>parent["science_files"],
    )
    report["output_files"]=Dict(
        p=>hashfile(joinpath(out, p)) for
        p in readdir(out) if isfile(joinpath(out, p)) && !haskey(files, p)
    )
    toml(joinpath(out, "audit.toml"), report)
    println(
        "Terminal $(size(A)); forward difference=$max_difference; witness residual=$(report["maximum_terminal_witness_residual_K"])",
    )
end
