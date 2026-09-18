function r4_science_hashes()
    hashes=r2_science_hashes()
    root=normpath(joinpath(@__DIR__, "..", ".."))
    for rel in (
        "scripts/r3_setup.jl",
        "scripts/r4_setup.jl",
        "scripts/run_r4.jl",
        "scripts/study_r4.jl",
        "scripts/freeze_r4.jl",
        "configs/r4/study.toml",
        "scripts/freeze_r4_baseline.jl",
        "scripts/study_r4_baseline.jl",
        "configs/r4/baseline/study.toml",
        "scripts/study_r4_bargaining.jl",
        "configs/r4/bargaining-study.toml",
        "scripts/study_r4_tspa.jl",
        "configs/r4/tspa-study.toml",
        "scripts/study_r4_distributed.jl",
        "configs/r4/distributed-study.toml",
        "scripts/study_r4_discrete.jl",
        "configs/r4/discrete-study.toml",
    )
        hashes[rel]=bytes2hex(sha256(read(joinpath(root, rel))))
    end
    return hashes
end

function r4_solve_stage(
    c,
    spec,
    optimizer,
    deadline;
    stage = :central,
    actor = 0,
    frozen = nothing,
    enumerate_battery = false,
    build_options = (;),
)
    start=time()
    T=c.data["T"]
    has_battery=any(
        i->(stage==:trading ? i>1 : stage!=:local || i==actor)&&c.data["actors"][i]["BS_power_max"]>0,
        1:3,
    )
    fixed=get(build_options, :modes, nothing)
    fixed!==nothing && enumerate_battery && error("固定模式与枚举不能同时指定")
    patterns=fixed!==nothing ? [fixed] :
             enumerate_battery && has_battery ? [[(n>>(t-1))&1 for t in 1:T] for n in 0:(2^T-1)] :
             [nothing]
    logs=Dict{String,Any}[]
    best=nothing
    bestcost=Inf
    result=Dict{String,Any}(
        "input_sha256"=>c.sha256,
        "spec"=>r4_spec(spec, c),
        "stage"=>String(stage),
        "actor"=>actor,
    )
    for pattern in patterns
        time()>=deadline && break
        log=Dict{String,Any}(
            "mode"=>pattern===nothing ? "binary" : join(pattern),
            "termination"=>"NOT_RUN",
        )
        push!(logs, log)
        try
            b=build_r4_model(
                c;
                spec,
                optimizer,
                stage,
                actor,
                frozen,
                modes = pattern,
                build_options...,
            )
            remaining=deadline-time()
            remaining<=0 && (log["termination"] = "TIME_LIMIT"; break)
            set_silent(b.model)
            set_time_limit_sec(b.model, remaining)
            optimize!(b.model)
            log["termination"]=string(termination_status(b.model))
            log["primal"]=string(primal_status(b.model))
            log["solver"]=solver_name(b.model)
            log["model_types"]=b.model_types
            log["model_class"]=b.model_class
            if has_values(b.model) &&
               primal_status(b.model) in (MOI.FEASIBLE_POINT, MOI.NEARLY_FEASIBLE_POINT)
                obj=objective_value(b.model)
                log["objective"]=obj
                if obj<bestcost
                    bestcost=obj
                    best=Dict(k=>r2_extract(x) for (k, x) in b.variables)
                end
            end
            try
                bound=objective_bound(b.model)
                r2_valid_bound(bound, log["solver"]) && (log["bound"]=bound)
            catch err
                err isa InterruptException && rethrow()
                log["bound_status"]="unavailable"
            end
            if !haskey(log, "bound") && dual_status(b.model)==MOI.FEASIBLE_POINT
                try
                    dualbound=dual_objective_value(b.model)
                    if isfinite(dualbound)
                        log["bound"]=dualbound
                        log["bound_status"]="dual_objective"
                    end
                catch err
                    err isa InterruptException && rethrow()
                end
            end
        catch err
            err isa InterruptException && rethrow()
            message=sprint(showerror, err)
            if occursin(r"(?i)license|licence", message)
                log["termination"]="LICENSE_MISSING"
            elseif occursin(r"(?i)not support|unsupported", message)
                log["termination"]="UNSUPPORTED"
            else
                # 不把构造错误伪装为不可行；保留错误类别，具体日志在调用侧定位。
                log["termination"]="OTHER_ERROR"
            end
            log["error_type"]=string(typeof(err))
            log["error_summary"]=replace(message, r"[A-Za-z]:[\\/][^\s\n]*"=>"[local path]")
            break
        end
    end
    status=any(x["termination"]=="LICENSE_MISSING" for x in logs) ? "license_missing" :
           r2_status(logs, length(patterns), best!==nothing, time()>=deadline)
    result["status"]=status
    result["solves"]=logs
    result["elapsed_sec"]=time()-start
    result["enumeration_expected"]=length(patterns)
    if best!==nothing
        result["values"]=best
        result["solver_objective"]=bestcost
    end
    complete=length(logs)==length(patterns)
    bounded=all(x["termination"]=="INFEASIBLE" || haskey(x, "bound") for x in logs)
    if complete && bounded && best!==nothing
        bounds=[x["bound"] for x in logs if x["termination"]!="INFEASIBLE"]
        if !isempty(bounds)
            result["objective_bound"]=minimum(bounds)
            result["relative_gap"]=abs(bestcost-minimum(bounds))/max(1, abs(bestcost))
        end
    end
    result["cost_optimization_complete"]=status=="solver_optimal" &&
                                         get(result, "relative_gap", Inf)<=1e-4
    return result
end

"""
    solve_r4_case(case; optimizer, spec=R4Spec(), enumerate_battery=false, budget_sec=600)

共享墙钟预算包含所有建模/枚举/AG0局部求解。AG0冻结两主体计划后才求网络，不暗调计划。
Gurobi可解互斥和原电网等式；Clarabel仅在显式枚举模式下求凸子问题。
保留不可行、缺许可、数值失败、时限及界；不自动切换电网版本。
"""
function solve_r4_case(
    c::R4Case;
    optimizer,
    spec = R4Spec(),
    enumerate_battery = false,
    budget_sec = 600.0,
)
    isfinite(budget_sec)&&budget_sec>0 || error("预算须为有限正数")
    enumerate_battery && c.data["T"]>10 && error("枚举仅用于小系统")
    start=time()
    deadline=start+budget_sec
    hashes=r4_science_hashes()
    locals=Dict{String,Any}[]
    if spec.operation==:independent
        for i in (2, 3)
            r=r4_solve_stage(
                c,
                spec,
                optimizer,
                deadline;
                stage = :local,
                actor = i,
                enumerate_battery,
            )
            r["validation"]=validate_r4_solution(c, r)
            push!(locals, r)
            r["validation"]["model_pass"] || break
        end
        if length(locals)==2 && all(x["validation"]["model_pass"] for x in locals)
            r=r4_solve_stage(
                c,
                spec,
                optimizer,
                deadline;
                stage = :network,
                frozen = locals,
                enumerate_battery,
            )
            r["status"]=="infeasible_certified" && (r["status"]="network_infeasible_certified")
        else
            r=Dict{String,Any}(
                "input_sha256"=>c.sha256,
                "spec"=>r4_spec(spec, c),
                "status"=>"local_stage_failed",
                "failed_stage_status"=>last(locals)["status"],
                "cost_optimization_complete"=>false,
            )
        end
    else
        r=r4_solve_stage(c, spec, optimizer, deadline; enumerate_battery)
    end
    r["local_stages"]=locals
    r["cost_optimization_complete"] &=
        all(get(x, "cost_optimization_complete", false) for x in locals)
    r["elapsed_sec"]=time()-start
    r["budget_sec"]=Float64(budget_sec)
    r["source_hashes_at_solve"]=hashes
    hashes==r4_science_hashes() || error("求解期间源码改变，本次运行不能封存")
    r["validation"]=validate_r4_solution(c, r)
    if haskey(r, "values")
        r["ledger"]=r4_ledger(
            c,
            r["values"];
            p2p_enabled = spec.operation==:central&&c.data["p2p_enabled"],
        )
        r["operating_cost"]=r["ledger"]["operating_cost"]
    end
    return r
end

"""
    save_r4_run(case, result; directory="results/runs/r4", run_id=...)

创建不可覆盖运行目录，保存输入、完整阶段/解/验证、账本和哈希。源码与求解时必须一致。
每项运行单独保存环境与源码快照；失败运行同样保存，金额目标与求解阶段分离。
"""
function save_r4_run(
    c::R4Case,
    r;
    directory = joinpath("results", "runs", "r4"),
    run_id = string(uuid4()),
)
    occursin(r"^[A-Za-z0-9_-]+$", run_id) || error("运行ID含非法路径")
    r["input_sha256"]==c.sha256 || error("输入不匹配")
    r["source_hashes_at_solve"]==r4_science_hashes() || error("源码已变，拒绝冒充原运行")
    path=joinpath(directory, run_id)
    ispath(path) && error("不覆盖原运行")
    mkpath(path)
    write(joinpath(path, "input.toml"), c.source_text)
    out=deepcopy(r)
    out["run_id"]=run_id
    write(joinpath(path, "result.toml"), r4_text(out))
    root=normpath(joinpath(@__DIR__, "..", ".."))
    paths=sort(collect(keys(r["source_hashes_at_solve"])))
    append!(
        paths,
        [
            "Project.toml",
            "Manifest.toml",
            "tools/solvers/Project.toml",
            "tools/solvers/Manifest.toml",
        ],
    )
    for rel in paths
        isfile(joinpath(root, rel)) || continue
        dest=joinpath(path, "snapshot", rel)
        mkpath(dirname(dest))
        cp(joinpath(root, rel), dest)
    end
    hashes=Dict{String,String}()
    for (dir, _, files) in walkdir(path), file in files
        f=joinpath(dir, file)
        hashes[replace(relpath(f, path), '\\'=>'/')]=bytes2hex(sha256(read(f)))
    end
    write(joinpath(path, "hashes.toml"), r4_text(Dict("sha256"=>hashes)))
    return abspath(path)
end

"""
    read_r4_run(directory)

检查运行目录的完整文件清单/哈希，并从保存数值重新验收。不会求解、迁移或改写旧记录。
哈希用于发现意外篡改，不是外部数字签名。返回case、result及重新计算的validation。
"""
function read_r4_run(path::AbstractString)
    hashes=TOML.parsefile(joinpath(path, "hashes.toml"))["sha256"]
    actual=Set{String}()
    for (dir, _, files) in walkdir(path), file in files
        rel=replace(relpath(joinpath(dir, file), path), '\\'=>'/')
        rel=="hashes.toml" && continue
        push!(actual, rel)
    end
    actual==Set(keys(hashes)) || error("保存文件清单改变")
    for (rel, hash) in hashes
        !isabspath(rel) && !(".." in split(rel, '/')) || error("非法存档路径")
        bytes2hex(sha256(read(joinpath(path, rel))))==hash || error("运行文件哈希不符: "*rel)
    end
    c=load_r4_case(joinpath(path, "input.toml"))
    r=TOML.parsefile(joinpath(path, "result.toml"))
    for local_run in get(r, "local_stages", Any[])
        validate_r4_solution(c, local_run)==local_run["validation"] || error("局部验收重读不一致")
    end
    val=validate_r4_solution(c, r)
    val==r["validation"] || error("运行验收重读不一致")
    haskey(r, "values") &&
        r4_ledger(
            c,
            r["values"];
            p2p_enabled = r["spec"]["operation"]=="central"&&c.data["p2p_enabled"],
        )!=r["ledger"] &&
        error("账本重读不一致")
    return (; case = c, result = r, validation = val)
end

"""
    compare_r4_runs(directories)

只比较同输入运行；AG0未通过网络与原电网检查时不生成可实施收益百分比。
输出模型、热能流、电网原等式、账本及费用求解状态，松弛成本不是收益承诺。
"""
function compare_r4_runs(paths)
    runs=read_r4_run.(paths)
    length(unique(x.case.sha256 for x in runs))==1 || error("不同配置不得作同输入收益比较")
    return [
        Dict(
            "run_id"=>x.result["run_id"],
            "operation"=>x.result["spec"]["operation"],
            "electric"=>x.result["spec"]["electric"],
            "status"=>x.result["status"],
            "model_pass"=>x.validation["model_pass"],
            "electric_original_pass"=>x.validation["electric_original_pass"],
            "heat_pass"=>x.validation["heat_pass"],
            "ledger_pass"=>x.validation["ledger_pass"],
            "operating_cost"=>get(x.result, "operating_cost", NaN),
            "cost_optimization_complete"=>x.result["cost_optimization_complete"],
        ) for x in runs
    ]
end

"""
    plot_r4_run(directory; output=...)

只读已保存R4运行并重绘F04/F10/F12，不重新求解。使用docs绘图环境执行scripts/plot_r4.jl，
该脚本装载CairoMakie后为本接口注册实现，普通模块导入不加载绘图库。
"""
function plot_r4_run end
