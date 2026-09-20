const R7_RECOVERY_SOLVE_FILE = @__FILE__

"""
    solve_r7_recovery(case, fault; optimizer, fixed_z=nothing, budget_sec=60)

在共享截止时间内构建并求解一个固定故障恢复问题，目标为加权失供MWh。
保存有效最小化下界、可行值和独立验算；失败不填零解，也不变更模型或求解器重试。
"""
function solve_r7_recovery(
    c::R7RecoveryCase,
    gamma;
    optimizer,
    fixed_z = nothing,
    budget_sec = 60.0,
    deadline = nothing,
)
    r7_recovery_assert(c)
    r7_check_fault(c, gamma)
    isfinite(budget_sec) && budget_sec>=0 || error("恢复预算错误")
    start=time()
    stop=deadline===nothing ? start+budget_sec : min(deadline, start+budget_sec)
    r=Dict{String,Any}(
        "schema"=>"r7-recovery-result-v1",
        "version"=>r7_recovery_version(c),
        "run_id"=>"r7-recovery-"*string(uuid4()),
        "case_sha256"=>c.sha256,
        "fault"=>Int.(gamma),
        "objective_kind"=>"expected_unserved_energy_MWh",
        "preplan_id"=>c.data["preplan_id"],
        "preplan_optimality_verified"=>false,
        "status"=>"budget_exhausted",
        "termination_status"=>"NOT_RUN",
        "julia_version"=>string(VERSION),
        "requested_budget_sec"=>Float64(budget_sec),
        "optimizer_request"=>sprint(show, optimizer),
        "utc"=>string(now(UTC)),
        "source_hashes_at_solve"=>r7_recovery_science_hashes(),
    )
    fixed_z===nothing || (r["fixed_z"]=Int.(fixed_z))
    if time()<stop
        try
            b=build_r7_recovery(c, gamma; optimizer, fixed_z)
            r["model_class"]=b.model_class
            r["formula_ids"]=sort(collect(keys(b.constraints)))
            set_silent(b.model)
            remaining=stop-time()
            if remaining>0
                set_time_limit_sec(b.model, remaining)
                optimize!(b.model)
                s=termination_status(b.model)
                r["termination_status"]=string(s)
                r["raw_status"]=raw_status(b.model)
                r["solver"]=solver_name(b.model)
                r["primal_status"]=string(primal_status(b.model))
                r["status"]=s==MOI.OPTIMAL ? "solver_optimal" :
                            s==MOI.INFEASIBLE ? "infeasible_certified" :
                            s==MOI.TIME_LIMIT ?
                            (
                    has_values(b.model) ? "time_limit_with_incumbent" : "time_limit_no_solution"
                ) : "solver_"*lowercase(string(s))
                if has_values(b.model) &&
                   primal_status(b.model) in (MOI.FEASIBLE_POINT, MOI.NEARLY_FEASIBLE_POINT)
                    r["values"]=Dict(k=>r7_pack(value.(a)) for (k, a) in b.variables)
                    r["solver_objective_MWh"]=objective_value(b.model)
                end
                try
                    lb=objective_bound(b.model)
                    isfinite(lb) && (r["lower_bound_MWh"]=Float64(lb))
                catch err
                    r["bound_unavailable"]=sprint(showerror, err)
                end
            end
        catch err
            r["error"]=sprint(showerror, err)
            r["status"]=occursin("licen", lowercase(r["error"])) ? "license_unavailable" :
                        "solver_or_build_error"
        end
    end
    r["elapsed_sec"]=time()-start
    r["validation"]=validate_r7_recovery(c, r)
    r["candidate_accepted"]=r["validation"]["model_pass"]
    r["loss_optimization_complete"]=r["candidate_accepted"] && r["validation"]["optimality_pass"]
    r
end

"""
    enumerate_r7_recovery(case, fault; optimizer, budget_sec=60)

最多12条电支路的小系统独立拓扑穷举，固定每个允许森林后解连续LP。
所有模式共享预算；未完成模式保留，未知模式的失供下界仅使用非负性0，不伪造全枚举证书。
"""
function enumerate_r7_recovery(c::R7RecoveryCase, gamma; optimizer, budget_sec = 60.0)
    r7_recovery_assert(c)
    r7_check_fault(c, gamma)
    isfinite(budget_sec) && budget_sec>=0 || error("枚举预算错误")
    start=time()
    stop=start+budget_sec
    L=length(c.data["electric"]["lines"])
    L<=12 || error("恢复拓扑穷举限12条线路；不能截断后称全局证书")
    runs=Dict{String,Any}[]
    scanned=0
    lower, upper=Inf, Inf
    best=0
    for mask in 0:(2^L-1)
        time()<stop || break
        z=[(mask >> (i-1)) & 1 for i in 1:L]
        scanned+=1
        r7_topology_roots(c, gamma, z)===nothing && continue
        r=solve_r7_recovery(
            c,
            gamma;
            optimizer,
            fixed_z = z,
            budget_sec = max(0, stop-time()),
            deadline = stop,
        )
        push!(runs, r)
        lb=r["status"]=="infeasible_certified" ? Inf : get(r, "lower_bound_MWh", 0.0)
        lower=min(lower, lb)
        if r["candidate_accepted"] && r["validation"]["loss_MWh"]<upper
            upper=r["validation"]["loss_MWh"]
            best=length(runs)
        end
    end
    complete=scanned==2^L
    complete || (lower=min(lower, 0.0))
    Dict(
        "schema"=>"r7-topology-enumeration-v1",
        "case_sha256"=>c.sha256,
        "fault"=>Int.(gamma),
        "topologies_scanned"=>scanned,
        "topologies_expected"=>2^L,
        "all_topologies_scanned"=>complete,
        "runs"=>runs,
        "best_index"=>best,
        "lower_bound_MWh"=>lower,
        "upper_bound_MWh"=>upper,
        "gap_certified"=>complete&&isfinite(upper)&&-1e-6<=(upper-lower)/max(1, abs(upper))<=1e-4,
        "infeasible_certified"=>complete&&lower==Inf,
        "elapsed_sec"=>time()-start,
    )
end

"""
    audit_r7_faults(case; optimizer, budget_sec=600, deadline=nothing)

对同一显式灾前状态枚举全部允许故障，各恢复MILP共享总预算，按A6分开最坏失供上下界。
覆盖全部故障的可行恢复上界才可认证安全；单故障有效下界可认证违反。
它是微型故障对手基准，不是已实现嵌套C&CG，也不证明给定灾前状态来自最优正常运行。
"""
function audit_r7_faults(c::R7RecoveryCase; optimizer, budget_sec = 600.0, deadline = nothing)
    isfinite(budget_sec) && budget_sec>=0 || error("故障审计预算错误")
    deadline===nothing || isfinite(deadline) || error("故障审计截止时间错误")
    start=time()
    stop=deadline===nothing ? start+budget_sec : min(deadline, start+budget_sec)
    faults=r7_faults(c)
    runs=Dict{String,Any}[]
    lower=0.0
    upper=0.0
    for gamma in faults
        time()<stop || break
        r=solve_r7_recovery(c, gamma; optimizer, budget_sec = max(0, stop-time()), deadline = stop)
        push!(runs, r)
        lower=max(lower, r["status"]=="infeasible_certified" ? Inf : get(r, "lower_bound_MWh", 0.0))
        upper=max(upper, r["candidate_accepted"] ? r["validation"]["loss_MWh"] : Inf)
    end
    complete=length(runs)==length(faults)
    complete || (upper=Inf)
    limit=c.data["loss_limit_MWh"]
    tol=1e-6*(1+max(1, limit))
    status=upper<=limit+tol ? "safe_adopted_model" :
           lower>limit+tol ? "violation_certified" : "unresolved"
    Dict(
        "schema"=>"r7-fault-audit-v1",
        "case_sha256"=>c.sha256,
        "preplan_id"=>c.data["preplan_id"],
        "status"=>status,
        "all_faults_attempted"=>complete,
        "expected_faults"=>length(faults),
        "runs"=>runs,
        "lower_bound_MWh"=>lower,
        "upper_bound_MWh"=>upper,
        "loss_limit_MWh"=>limit,
        "elapsed_sec"=>time()-start,
        "nested_algorithm"=>false,
        "preplan_optimality_verified"=>false,
    )
end
