r3_clock() = time_ns()/1e9

# 界和对偶是可选证据；属性不可用不应丢弃已有原始解，也不能伪造数值界。
function r3_optional_attribute(getter)
    try
        return (value = getter(), error = nothing)
    catch err
        message=sprint(showerror, err)
        if err isa Union{MOI.UnsupportedAttribute,MOI.GetAttributeNotAllowed} ||
           occursin("Gurobi Error 10005: Unable to retrieve attribute", message)
            return (value = nothing, error = message)
        end
        rethrow()
    end
end

function r3_solve(
    c,
    builder,
    optimizer;
    budget_sec = 60.0,
    deadline = Inf,
    sensitivity = false,
    sensitivity_witness = false,
)
    start = r3_clock()
    stop = min(deadline, start+budget_sec)
    result = Dict{String,Any}(
        "input_sha256"=>c.sha256,
        "spec"=>r2_spec_dict(R2Spec()),
        "fixed_flows"=>true,
        "case_origin"=>"synthetic",
        "source_hashes_at_solve"=>r2_science_hashes(),
        "threads"=>1,
        "seed"=>0,
        "budget_sec"=>max(0, stop-start),
    )
    if stop <= r3_clock()
        merge!(result, Dict("status"=>"time_limit_no_solution", "elapsed_sec"=>r3_clock()-start))
        return result
    end
    b = builder()
    result["spec"]=r2_spec_dict(b.spec)
    result["rescale_cones"]=hasproperty(b, :rescale_cones) && b.rescale_cones
    if hasproperty(b, :operation) && !isnothing(b.operation)
        result["operation"]=r3_operation_dict(b.operation)
        result["operation_sha256"]=r3_operation_hash(result["operation"])
    end
    merge!(
        result,
        Dict(
            "variant"=>b.variant,
            "objective_kind"=>b.objective_kind,
            "fixed_flows"=>b.fixed_flows,
            "flow_sha256"=>r2_flow_hash(b.flow_schedule),
            "class"=>b.class,
        ),
    )
    result[b.fixed_flows ? "flow_schedule" : "initial_flow"] = r2_extract(b.flow_schedule)
    result["elastic_rows"] =
        [Dict(string(k)=>getfield(row, k) for k in keys(row)) for row in b.elastic_rows]
    if isnothing(optimizer)
        merge!(result, Dict("status"=>"not_run_solver", "elapsed_sec"=>r3_clock()-start))
        return result
    end
    try
        set_optimizer(b.model, optimizer)
        set_silent(b.model)
        name = solver_name(b.model)
        result["solver"] = name
        if occursin("Clarabel", name)
            for (k, v) in
                ("max_threads"=>1, "tol_gap_abs"=>1e-9, "tol_gap_rel"=>1e-9, "tol_feas"=>1e-9)
                set_optimizer_attribute(b.model, k, v)
            end
        elseif occursin("Gurobi", name)
            for (k, v) in (
                "Threads"=>1,
                "Seed"=>0,
                "NonConvex"=>2,
                "FeasibilityTol"=>1e-9,
                "OptimalityTol"=>1e-9,
                "BarConvTol"=>1e-10,
                "MIPGap"=>1e-6,
            )
                set_optimizer_attribute(b.model, k, v)
            end
            b.class == "SOCP" && set_optimizer_attribute(b.model, "QCPDual", 1)
            # 对偶采集额外收紧QCP停止容差；旧调用的默认求解参数保持不变。
            if sensitivity && b.class=="SOCP"
                set_optimizer_attribute(b.model, "BarQCPConvTol", 1e-10)
                result["sensitivity_qcp_tolerance"]=1e-10
            end
        end
        remaining = stop-r3_clock()
        if remaining <= 0
            merge!(
                result,
                Dict("status"=>"time_limit_no_solution", "elapsed_sec"=>r3_clock()-start),
            )
            return result
        end
        result["build_sec"] = r3_clock()-start
        set_time_limit_sec(b.model, remaining)
        optimize!(b.model)
        term, primal = string(termination_status(b.model)), string(primal_status(b.model))
        entry = Dict("termination"=>term, "primal"=>primal)
        has_solution = has_values(b.model) && primal_status(b.model) == MOI.FEASIBLE_POINT
        result["status"] = r2_status([entry], 1, has_solution, r3_clock()>=stop)
        result["termination"], result["primal"] = term, primal
        result["JuMP_version"] = string(Base.pkgversion(JuMP))
        try
            result["solver_version"] = MOI.get(backend(b.model), MOI.SolverVersion())
        catch err
            err isa Union{MOI.UnsupportedAttribute,MOI.GetAttributeNotAllowed} || rethrow()
        end
        if has_solution
            result["values"] = Dict(k=>r2_extract(v) for (k, v) in b.variables)
            result["solver_objective"] = objective_value(b.model)
            result["operating_cost"] = r3_operating_cost(c, result["values"])
            # objective保留R2兼容意义：始终是运行成本；优化目标另存，不复制目标界。
            result["objective"] = result["operating_cost"]
        end
        available=r3_optional_attribute(()->objective_bound(b.model))
        isnothing(available.error) || (result["bound_error"]=available.error)
        if !isnothing(available.value)
            bound = available.value
            result["raw_solver_bound"] = bound
            if r2_valid_bound(bound, name)
                result["solver_bound"] = bound
                result["bound_objective_kind"] = b.objective_kind
            end
        end
        if !haskey(result, "solver_bound") && dual_status(b.model)==MOI.FEASIBLE_POINT
            available=r3_optional_attribute(()->dual_objective_value(b.model))
            isnothing(available.error) || (result["dual_bound_error"]=available.error)
            bound=available.value
            if !isnothing(bound) && r2_valid_bound(bound, name)
                result["solver_bound"] = bound
                result["bound_objective_kind"] = b.objective_kind
            end
        end
        if has_solution && haskey(result, "solver_bound")
            result["solver_relative_gap"] =
                max(0, result["solver_objective"]-result["solver_bound"])/max(
                    1,
                    abs(result["solver_objective"]),
                )
        end
        if sensitivity && has_solution
            result["sensitivity"] = r3_value_sensitivity(c, b)
            sensitivity_witness &&
                (result["sensitivity_primal_order"] = value.(all_variables(b.model)))
        end
    catch err
        if err isa Union{MOI.UnsupportedConstraint,MOI.UnsupportedAttribute}
            result["status"] = "unsupported_solver"
        elseif occursin("license", lowercase(sprint(showerror, err)))
            result["status"] = "not_run_license"
        else
            rethrow()
        end
    end
    result["elapsed_sec"] = r3_clock()-start
    return result
end

"""
    save_r3_run(case, result; root="results/runs", run_id=...)

独立保存R3全部阶段、原始数值、配置、源代码/环境快照、哈希与逐式残差，不覆盖旧运行。
保存前重验最终候选，并拒绝求解后科学源码改变；输入、流量、修正目标和运行成本分别记录。
"""
function save_r3_run(
    c::R2Case,
    result;
    root = "results/runs",
    run_id = "r3-"*Dates.format(now(UTC), "yyyymmddTHHMMSS")*"-"*string(uuid4())[1:8],
)
    occursin(r"^[A-Za-z0-9_-]+$", run_id) || throw(ArgumentError("非法运行ID"))
    result["source_hashes_at_solve"]==r2_science_hashes() ||
        throw(ArgumentError("求解后源码已改变，不能保存为同一证据"))
    report = validate_r3_solution(c, result)
    mkpath(root)
    dir = joinpath(root, run_id)
    mkdir(dir)
    toml(name, obj) = open(io->TOML.print(io, obj; sorted = true), joinpath(dir, name), "w")
    toml("case.toml", c.data)
    toml("run.toml", result)
    records, residuals = NamedTuple[], NamedTuple[]
    for (i, stage) in enumerate(result["stages"])
        validation = report.stages[i]
        distance =
            haskey(stage, "values") && haskey(result, "initial_flow") ?
            r3_distance(
                c,
                r2_flow_matrix(c, stage["values"]["m_pipe"]),
                r2_flow_matrix(c, result["initial_flow"]),
            ) : missing
        push!(
            records,
            (
                run_id,
                stage = i,
                name = stage["stage"],
                variant = get(stage, "variant", get(stage["spec"], "formulation", "")),
                status = stage["status"],
                objective_kind = get(stage, "objective_kind", "operating_cost"),
                solver_objective = get(stage, "solver_objective", get(stage, "objective", missing)),
                operating_cost = get(stage, "operating_cost", get(stage, "objective", missing)),
                solver_bound = get(stage, "solver_bound", get(stage, "bound", missing)),
                relative_gap = get(
                    stage,
                    "solver_relative_gap",
                    get(stage, "relative_gap", missing),
                ),
                flow_distance = distance,
                elapsed_sec = stage["elapsed_sec"],
                model_pass = validation.model_pass,
                physical_pass = validation.physical_pass,
            ),
        )
        append!(
            residuals,
            [merge((run_id, stage = i, name = stage["stage"]), row) for row in validation.rows],
        )
    end
    !isempty(records) && CSV.write(joinpath(dir, "stages.csv"), records)
    !isempty(residuals) && CSV.write(joinpath(dir, "residuals.csv"), residuals)
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
    for folder in ("src", "scripts", "configs/r3"),
        (directory, _, files) in walkdir(joinpath(project, folder)),
        file in files

        push!(paths, replace(relpath(joinpath(directory, file), project), '\\'=>'/'))
    end
    for p in paths
        bytes = read(joinpath(project, p))
        hashes[p] = bytes2hex(sha256(bytes))
        dest = joinpath(dir, "code", p)
        mkpath(dirname(dest))
        write(dest, bytes)
    end
    artifact_hashes = Dict(
        file=>bytes2hex(sha256(read(joinpath(dir, file)))) for
        file in readdir(dir) if isfile(joinpath(dir, file))
    )
    toml(
        "metadata.toml",
        Dict(
            "schema"=>"r3-evidence-v1",
            "run_id"=>run_id,
            "utc"=>string(now(UTC)),
            "julia"=>string(VERSION),
            "os"=>string(Sys.KERNEL),
            "input_sha256"=>c.sha256,
            "head"=>strip(read(`git -C $project rev-parse HEAD`, String)),
            "dirty"=>!isempty(read(`git -C $project status --porcelain`, String)),
            "entrypoint"=>basename(PROGRAM_FILE),
            "arguments"=>[isabspath(a) ? basename(a) : a for a in ARGS],
            "artifacts"=>artifact_hashes,
            "source_hashes"=>hashes,
            "snapshot_included"=>true,
            "physical_pass"=>report.physical_pass,
        ),
    )
    return dir
end

"""
    read_r3_run(directory)

重读已保存R3案例及所有阶段；验证文件哈希与输入关联，再独立检查最终结果。
公开摘要可以明确不携带代码副本，但必须保留代码哈希；不根据保存的pass标志判断成功。
"""
function read_r3_run(dir)
    meta = TOML.parsefile(joinpath(dir, "metadata.toml"))
    meta["schema"]=="r3-evidence-v1" || throw(ArgumentError("未知R3证据格式"))
    function checkfile(prefix, p, hash)
        !isabspath(p) && !(".." in split(replace(p, '\\'=>'/'), '/')) ||
            throw(ArgumentError("证据路径越界"))
        bytes2hex(sha256(read(joinpath(dir, prefix, p))))==hash ||
            throw(ArgumentError("R3证据哈希不匹配：$p"))
    end
    all(haskey(meta["artifacts"], p) for p in ("case.toml", "run.toml")) ||
        throw(ArgumentError("证据清单缺少必需文件"))
    for (p, h) in meta["artifacts"]
        checkfile("", p, h)
    end
    if get(meta, "snapshot_included", false)
        for (p, h) in meta["source_hashes"]
            checkfile("code", p, h)
        end
    end
    c = load_r2_case(joinpath(dir, "case.toml"))
    c = R2Case(c.data, meta["input_sha256"])
    result = TOML.parsefile(joinpath(dir, "run.toml"))
    validation = validate_r3_solution(c, result)
    return (case = c, result, metadata = meta, validation)
end

"""
    plot_r3_run(directory; output)

读取R3保存结果绘制F04/F05与阶段对照；不调用求解器。实现由docs环境的scripts/plot_r3.jl加载，
普通模型导入不加载CairoMakie，也不申请商业许可。
"""
function plot_r3_run end

"""
    repair_r3_flow(case, initial_flow; optimizer, budget_sec=300, deadline=Inf)

项目方法r3_direct_repair_v1：详细WMM加电/水松弛前等式，最小化归一化流量绝对改动。
流量单位kg/s，目标无量纲；历史、负荷和设备边界不变，退化流量盒直接固定。
共享deadline覆盖建模与求解；返回实际目标、界、成本及原始停止状态，不保证预算内全局最优。
"""
function repair_r3_flow(c::R2Case, initial_flow; optimizer, budget_sec = 300.0, deadline = Inf)
    isfinite(budget_sec) && budget_sec>0 || throw(ArgumentError("修正预算必须为正"))
    m = r2_flow_matrix(c, initial_flow)
    return r3_solve(c, ()->r3_build_repair(c, m), optimizer; budget_sec, deadline)
end

"""
    solve_r3_feasibility(case; optimizer=nothing, convex_optimizer=optimizer,
                         initial_flow=nothing, initial_run=nothing, budget_sec=600)

R3可行性闭环：初始化、固定流量SP、κ重构、必要的诊断和项目直接修正、固定修正流量调度。
两个初值入口互斥；缺省用SCHPD初始化，无解不偷偷替换。initial_run必须为同输入的SCHPD已保存运行。
所有阶段共用截止时间：初值/SP/诊断各至多60秒，直接修正至多300秒，其余调度使用剩余预算。
返回完整阶段及最终候选编号；成功只表示本批采用关系通过，不是作者投影梯度复现。
"""
function solve_r3_feasibility(
    c::R2Case;
    optimizer = nothing,
    convex_optimizer = optimizer,
    initial_flow = nothing,
    initial_run = nothing,
    budget_sec = 600.0,
)
    isfinite(budget_sec) && 0<budget_sec<=600 || throw(ArgumentError("完整流程预算必须在(0,600]秒"))
    !isnothing(initial_flow) && !isnothing(initial_run) && throw(ArgumentError("初值入口互斥"))
    validate_r2_input(c.data)
    start = r3_clock()
    deadline = start+budget_sec
    stages = Dict{String,Any}[]
    out = Dict{String,Any}(
        "schema"=>"r3-run-v1",
        "input_sha256"=>c.sha256,
        "origin"=>"synthetic",
        "budget_sec"=>budget_sec,
        "stages"=>stages,
        "source_hashes_at_solve"=>r2_science_hashes(),
        "final_stage"=>0,
        "cost_optimization_complete"=>false,
    )
    function pushstage(name, r)
        r["stage"] = name
        report = validate_r3_solution(c, r)
        r["model_pass"], r["physics_pass"] = report.model_pass, report.physical_pass
        push!(stages, r)
        return r
    end
    function finish(status)
        out["status"] = status
        out["elapsed_sec"] = r3_clock()-start
        return out
    end
    function accept(index)
        out["final_stage"] = index
        r = stages[index]
        out["cost_optimization_complete"] =
            get(r, "objective_kind", "")=="operating_cost" && r["status"]=="solver_optimal"
        return finish(
            out["cost_optimization_complete"] ? "feasible_cost_optimized" : "feasible_incumbent",
        )
    end
    if !isnothing(initial_run)
        imported = read_r2_run(initial_run)
        imported.case.data == c.data && imported.case.sha256==c.sha256 ||
            throw(ArgumentError("初始化运行与案例不一致"))
        imported.result["spec"]["formulation"]=="schpd_mc_v1" ||
            throw(ArgumentError("导入初值必须为SCHPD运行"))
        init = deepcopy(imported.result)
        out["parent_run_id"] = imported.metadata["run_id"]
        out["parent_solution_sha256"] = imported.metadata["solution_sha256"]
        pushstage("initialization_imported", init)
        haskey(init, "values") && get(init, "model_pass", false) ||
            return finish("initialization_failed")
        initial_flow = init["values"]["m_pipe"]
    elseif isnothing(initial_flow)
        remaining = min(60.0, deadline-r3_clock())
        remaining>0 || return finish("budget_exhausted")
        if isnothing(optimizer)
            return finish("initialization_not_run_solver")
        end
        init = try
            solve_r2_case(
                c;
                optimizer,
                spec = R2Spec(; formulation = :schpd_mc_v1),
                budget_sec = remaining,
            )
        catch err
            reason =
                err isa Union{MOI.UnsupportedConstraint,MOI.UnsupportedAttribute} ?
                "unsupported_solver" :
                occursin("license", lowercase(sprint(showerror, err))) ? "not_run_license" : nothing
            isnothing(reason) && rethrow()
            Dict{String,Any}(
                "input_sha256"=>c.sha256,
                "spec"=>r2_spec_dict(R2Spec(; formulation = :schpd_mc_v1)),
                "fixed_flows"=>false,
                "status"=>reason,
                "elapsed_sec"=>r3_clock()-start,
            )
        end
        pushstage("initialization", init)
        haskey(init, "values") && get(init, "model_pass", false) ||
            return finish("initialization_failed")
        initial_flow = init["values"]["m_pipe"]
    end
    m0 = r2_flow_matrix(c, initial_flow)
    out["initial_flow"], out["initial_flow_sha256"] = r2_extract(m0), r2_flow_hash(m0)
    sp = pushstage(
        "fixed_dispatch",
        r3_solve(c, ()->build_r3_subproblem(c, m0), convex_optimizer; budget_sec = 60.0, deadline),
    )
    if sp["model_pass"]
        reconstructed = reconstruct_r3_pressure(c, sp)
        reconstructed["elapsed_sec"] = 0.0
        pushstage("pressure_reconstruction", reconstructed)
        reconstructed["physics_pass"] && return accept(length(stages))
        failures = filter(row -> !row.pass, validate_r3_solution(c, reconstructed).rows)
        if !isempty(failures) && all(row -> row.equation=="pre-SOC-electric", failures)
            fixed = pushstage(
                "fixed_physical",
                r3_solve(
                    c,
                    ()->build_r3_subproblem(c, m0; physical = true),
                    optimizer;
                    budget_sec = min(60.0, max(0, deadline-r3_clock())),
                    deadline,
                ),
            )
            fixed["physics_pass"] && return accept(length(stages))
        end
    end
    deadline>r3_clock() || return finish("budget_exhausted")
    pushstage(
        "diagnostic",
        r3_solve(
            c,
            ()->build_r3_subproblem(c, m0; mode = :diagnostic),
            convex_optimizer;
            budget_sec = 60.0,
            deadline,
        ),
    )
    deadline>r3_clock() || return finish("budget_exhausted")
    repaired =
        pushstage("direct_repair", repair_r3_flow(c, m0; optimizer, budget_sec = 300.0, deadline))
    repaired["physics_pass"] || return finish(
        repaired["status"]=="infeasible_certified" ? "infeasible_certified" : "repair_unresolved",
    )
    bestindex = length(stages)
    mr = r2_flow_matrix(c, repaired["values"]["m_pipe"])
    if deadline>r3_clock()
        polished = pushstage(
            "repaired_dispatch",
            r3_solve(
                c,
                ()->build_r3_subproblem(c, mr; physical = true),
                optimizer;
                budget_sec = max(0, deadline-r3_clock()),
                deadline,
            ),
        )
        if polished["physics_pass"] &&
           polished["operating_cost"] <=
           repaired["operating_cost"]+1e-6*max(1, abs(repaired["operating_cost"]))
            bestindex = length(stages)
        end
    end
    return accept(bestindex)
end
