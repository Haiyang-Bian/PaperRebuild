function r2_spec_dict(spec)
    return Dict(string(k) => string(getfield(spec, k)) for k in fieldnames(R2Spec))
end
function r2_spec_from_dict(d)
    return R2Spec(; (Symbol(k) => Symbol(v) for (k, v) in d)...)
end
function r2_extract(v)
    a = Array(value.(v))
    return ndims(a) == 1 ? collect(a) : [collect(row) for row in eachrow(a)]
end

function r2_science_hashes()
    root = normpath(joinpath(@__DIR__, "..", ".."))
    hashes = Dict{String,String}()
    for (directory, _, files) in walkdir(joinpath(root, "src")), file in files
        endswith(file, ".jl") || continue
        path = joinpath(directory, file)
        hashes[replace(relpath(path, root), '\\'=>'/')] = bytes2hex(sha256(read(path)))
    end
    return hashes
end

# 原始停止事实优先；ALMOST/UNKNOWN 不伪装成时限或已认证最优。
function r2_status(logs, expected, has_solution, exhausted)
    terms = [x["termination"] for x in logs]
    "UNSUPPORTED" in terms && return "unsupported_solver"
    any(t -> t in ("NUMERICAL_ERROR", "OTHER_ERROR", "INVALID_MODEL"), terms) &&
        return "numerical_failure"
    any(t -> t in ("LOCALLY_SOLVED", "ALMOST_LOCALLY_SOLVED"), terms) && return "local_solution"
    complete =
        length(logs) == expected && all(
            x ->
                x["termination"] == "INFEASIBLE" ||
                (x["termination"] == "OPTIMAL" && get(x, "primal", "") == "FEASIBLE_POINT"),
            logs,
        )
    complete && return has_solution ? "solver_optimal" : "infeasible_certified"
    (exhausted || "TIME_LIMIT" in terms) &&
        return has_solution ? "time_limit_with_incumbent" : "time_limit_no_solution"
    return has_solution ? "incomplete_with_incumbent" : "incomplete_no_solution"
end

# region r2-solve
"""
    solve_r2_case(case; optimizer, spec=R2Spec(), fixed_flows=false, enumerate_mixing=false, budget_sec=600)

预算包含建模与所有枚举子问题；有解才读取数值。开放求解器可穷举微型主导入流选择，
最多64组合；未完成枚举不能报告全局最优。Gurobi许可由调用脚本提供，导入不申领许可。
返回版本、输入哈希、解/界、原始状态、实际模型类型和耗时；仅显式solver_log时让求解器写原始日志。
"""
function solve_r2_case(
    c::R2Case;
    optimizer,
    spec = R2Spec(),
    fixed_flows = false,
    enumerate_mixing = false,
    budget_sec = 600.0,
    solver_log = nothing,
)
    isfinite(budget_sec) && budget_sec > 0 || throw(ArgumentError("预算必须为有限正数"))
    start = time()
    result = Dict{String,Any}(
        "input_sha256" => c.sha256,
        "spec" => r2_spec_dict(spec),
        "fixed_flows" => fixed_flows,
        "budget_sec" => budget_sec,
        "case_origin" => "synthetic",
        "threads" => 1,
        "seed" => 0,
        "paper_match" => "blocked",
        "source_hashes_at_solve" => r2_science_hashes(),
    )
    if spec.formulation in (:wmm_literal, :schpd_literal)
        b = build_r2_model(c; spec)
        merge!(
            result,
            Dict("status" => "blocked", "issues" => b.issues, "elapsed_sec" => time()-start),
        )
        return result
    end
    counts = [k[4] for k in r2_choice_keys(c.data)]
    patterns = if enumerate_mixing && spec.mixing == :dominant
        prod(counts; init = 1) <= 64 || throw(ArgumentError("微型枚举超过64组合"))
        collect(Iterators.product((1:n for n in counts)...))[:]
    else
        [nothing]
    end
    logs = Dict{String,Any}[]
    best = Inf
    for pattern in patterns
        time()-start < budget_sec || break
        buildstart = time()
        b = build_r2_model(c; spec, optimizer, fixed_flows, choices = pattern)
        set_silent(b.model)
        if occursin("Clarabel", solver_name(b.model))
            set_optimizer_attribute(b.model, "max_threads", 1)
        elseif occursin("Gurobi", solver_name(b.model))
            set_optimizer_attribute(b.model, "Threads", 1)
            set_optimizer_attribute(b.model, "Seed", 0)
        end
        if !isnothing(solver_log)
            occursin("Gurobi", solver_name(b.model)) ||
                throw(ArgumentError("原始日志参数仅支持Gurobi"))
            set_optimizer_attribute(b.model, "LogFile", solver_log)
            set_optimizer_attribute(b.model, "LogToConsole", 0)
            set_optimizer_attribute(b.model, "OutputFlag", 1)
        end
        left = budget_sec-(time()-start)
        left > 0 || break
        set_time_limit_sec(b.model, left)
        entry = Dict{String,Any}(
            "pattern" => isnothing(pattern) ? "direct" : join(pattern, ","),
            "class" => b.class,
            "build_sec" => time()-buildstart,
        )
        solve_start = time()
        try
            optimize!(b.model)
        catch err
            # 不支持约束的求解器不能被读成数学不可行；未知程序错误继续抛出。
            if err isa Union{MOI.UnsupportedConstraint,MOI.UnsupportedAttribute}
                entry["termination"] = "UNSUPPORTED"
                push!(logs, entry)
                break
            end
            rethrow()
        end
        entry["solve_sec"] = time()-solve_start
        entry["termination"] = string(termination_status(b.model))
        entry["primal"] = string(primal_status(b.model))
        entry["solver"] = solver_name(b.model)
        entry["JuMP_version"] = string(Base.pkgversion(JuMP))
        try
            entry["solver_version"] = MOI.get(backend(b.model), MOI.SolverVersion())
        catch err
            err isa Union{MOI.UnsupportedAttribute,MOI.GetAttributeNotAllowed} || rethrow()
            entry["solver_version"] = "unavailable"
        end
        if primal_status(b.model) == MOI.FEASIBLE_POINT && has_values(b.model)
            entry["objective"] = objective_value(b.model)
            if entry["objective"] < best
                best = entry["objective"]
                result["objective"] = best
                result["values"] = Dict(k => r2_extract(v) for (k, v) in b.variables)
                result["class"] = b.class
                result["selected_pattern"] = entry["pattern"]
            end
        end
        try
            bound = objective_bound(b.model)
            isfinite(bound) && (entry["bound"] = bound)
        catch err
            err isa Union{MOI.UnsupportedAttribute,MOI.GetAttributeNotAllowed} || rethrow()
            if dual_status(b.model) == MOI.FEASIBLE_POINT
                entry["bound"] = dual_objective_value(b.model)
            end
        end
        push!(logs, entry)
    end
    result["status"] = r2_status(logs, length(patterns), isfinite(best), time()-start >= budget_sec)
    # 所有分支必须有有效下界（或已证不可行），才能汇总原枚举问题的下界。
    candidates = filter(x -> x["termination"] != "INFEASIBLE", logs)
    if length(logs) == length(patterns) &&
       !isempty(candidates) &&
       all(x -> haskey(x, "bound"), candidates)
        result["bound"] = minimum(x["bound"] for x in candidates)
        isfinite(best) && (result["relative_gap"] = max(0, best-result["bound"])/max(1, abs(best)))
    end
    result["subproblems"] = logs
    result["elapsed_sec"] = time()-start
    return result
end
# endregion r2-solve

# region r2-save
"""
    save_r2_run(case, result; root="results/runs", run_id=...)

不可覆盖地保存配置、解、独立验证、图源数据和精确源码快照。记录 Git HEAD/脏状态/差异哈希、
Julia与环境锁文件哈希；快照覆盖未提交源码和运行脚本，排除个人设置与凭据。
"""
function save_r2_run(
    c::R2Case,
    result;
    root = "results/runs",
    run_id = "r2-"*Dates.format(now(UTC), "yyyymmddTHHMMSS")*"-"*string(uuid4())[1:8],
)
    occursin(r"^[A-Za-z0-9_-]+$", run_id) || throw(ArgumentError("非法运行ID"))
    mkpath(root)
    dir = joinpath(root, run_id)
    mkdir(dir)
    toml(name, x) = open(io -> TOML.print(io, x; sorted = true), joinpath(dir, name), "w")
    toml("case.toml", c.data)
    toml("solution.toml", result)
    project = normpath(joinpath(@__DIR__, "..", ".."))
    hashes = Dict{String,String}()
    paths = [
        "Project.toml",
        "Manifest.toml",
        "tools/solvers/Project.toml",
        "tools/solvers/Manifest.toml",
        "docs/Project.toml",
        "docs/Manifest.toml",
    ]
    for folder in ("src", "scripts"),
        (directory, _, files) in walkdir(joinpath(project, folder)),
        file in files

        endswith(file, ".jl") &&
            push!(paths, replace(relpath(joinpath(directory, file), project), '\\'=>'/'))
    end
    for p in paths
        bytes = read(joinpath(project, p))
        hashes[p] = bytes2hex(sha256(bytes))
        dest = joinpath(dir, "code", p)
        mkpath(dirname(dest))
        write(dest, bytes)
    end
    scoped_diff = read(
        `git -C $project diff HEAD -- src scripts configs/r2 docs/reading/ch03 Project.toml Manifest.toml`,
        String,
    )
    write(joinpath(dir, "tracked-code.diff"), scoped_diff)
    toml(
        "metadata.toml",
        Dict(
            "run_id"=>run_id,
            "utc"=>string(now(UTC)),
            "julia"=>string(VERSION),
            "os"=>string(Sys.KERNEL),
            "cpu"=>Sys.CPU_NAME,
            "logical_cpus"=>Sys.CPU_THREADS,
            "command"=>join(vcat([basename(PROGRAM_FILE)], ARGS), " "),
            "head"=>strip(read(`git -C $project rev-parse HEAD`, String)),
            "dirty"=>!isempty(read(`git -C $project status --porcelain`, String)),
            "diff_sha256"=>bytes2hex(sha256(scoped_diff)),
            "hashes"=>hashes,
            "source_snapshot_matches_solve"=>get(result, "source_hashes_at_solve", Dict()) ==
                                             r2_science_hashes(),
            "input_sha256"=>c.sha256,
            "case_sha256"=>bytes2hex(sha256(read(joinpath(dir, "case.toml")))),
            "solution_sha256"=>bytes2hex(sha256(read(joinpath(dir, "solution.toml")))),
        ),
    )
    report = validate_r2_solution(c, result)
    toml(
        "validation.toml",
        Dict(
            "status"=>report.status,
            "model_pass"=>report.model_pass,
            "original_physics_pass"=>report.original_physics_pass,
            "paper_match"=>"blocked",
        ),
    )
    if !isempty(report.rows)
        CSV.write(joinpath(dir, "residuals.csv"), report.rows)
        s = result["values"]
        rows = NamedTuple[]
        for t in 1:c.data["T"], j in eachindex(c.data["heat"]["nodes"])
            push!(
                rows,
                (
                    run_id = run_id,
                    t = t,
                    time_h = t*c.data["dt_h"],
                    node = j,
                    tau_S_K = s["tau_S_mix"][j][t],
                    tau_R_K = s["tau_R_mix"][j][t],
                    H_MW = s["H_port"][j][t],
                    m_kg_s = s["m_port"][j][t],
                ),
            )
        end
        CSV.write(joinpath(dir, "timeseries.csv"), rows)
    end
    return dir
end

"""
    read_r2_run(dir)

读取不可变运行，核对输入与解的SHA，返回 case/result/metadata。篡改拒绝；不重新求解。
"""
function read_r2_run(dir)
    meta = TOML.parsefile(joinpath(dir, "metadata.toml"))
    c = load_r2_case(joinpath(dir, "case.toml"))
    c.sha256 == meta["case_sha256"] || throw(ArgumentError("输入副本哈希不匹配"))
    bytes2hex(sha256(read(joinpath(dir, "solution.toml")))) == meta["solution_sha256"] ||
        throw(ArgumentError("解文件哈希不匹配"))
    result = TOML.parsefile(joinpath(dir, "solution.toml"))
    result["input_sha256"] == meta["input_sha256"] || throw(ArgumentError("输入来源关联失效"))
    return (case = R2Case(c.data, meta["input_sha256"]), result = result, metadata = meta)
end

"""
    compare_r2_runs(reference_dir, candidate_dir)

仅比较相同输入哈希和流量固定方式的运行。区分同模型求解器差异与不同模型差异；
输出温度/热功率差与成本差，不把不同模型的差解释成最优间隙。缺解返回 no_comparison。
"""
function compare_r2_runs(a, b)
    x, y = read_r2_run(a), read_r2_run(b)
    get(x.metadata, "source_snapshot_matches_solve", false) &&
    get(y.metadata, "source_snapshot_matches_solve", false) ||
        throw(ArgumentError("缺少求解前后源码一致性证据，不能列为正式比较"))
    x.case.sha256 == y.case.sha256 && x.result["fixed_flows"] == y.result["fixed_flows"] ||
        throw(ArgumentError("比较必须使用同一输入与固定流量设置"))
    if !haskey(x.result, "values") || !haskey(y.result, "values")
        return (
            status = "no_comparison",
            rows = NamedTuple[],
            cost_difference = NaN,
            same_model = false,
        )
    end
    rows = NamedTuple[]
    for key in ("tau_S_mix", "tau_R_mix", "H_port"),
        j in eachindex(x.result["values"][key]),
        t in 1:x.case.data["T"]

        xv, yv = x.result["values"][key][j][t], y.result["values"][key][j][t]
        push!(
            rows,
            (
                quantity = key,
                node = j,
                t = t,
                reference = xv,
                candidate = yv,
                difference = yv-xv,
                unit = key == "H_port" ? "MW" : "K",
            ),
        )
    end
    return (
        status = "compared",
        rows = rows,
        cost_difference = y.result["objective"]-x.result["objective"],
        same_model = x.result["spec"] == y.result["spec"],
    )
end

"""
    plot_r2_run(dir; reference=nothing, output=joinpath(dir,"figures"))

从保存数据重绘 F04/F05；在 docs 环境加载 scripts/plot_r2.jl 后提供方法。
不加载求解器或重新求解，图源、单位、运行ID和配置随图保留。
"""
function plot_r2_run end
# endregion r2-save
