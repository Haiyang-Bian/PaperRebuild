"""
    solve_r7_transport_recovery(case, fault, spec; optimizer, fixed_z=nothing, budget_sec=600)

共享600秒以内预算构建并求解给定流量的详细热恢复；不以旧代理解固定设备或提供优化初值。
保存实际终止状态、有效条件下界和独立验证。不可行仅属于该流量、初态和子步定义。
"""
function solve_r7_transport_recovery(
    c,
    gamma,
    s;
    optimizer,
    fixed_z = nothing,
    fixed_battery_modes = nothing,
    budget_sec = 600.0,
)
    start=time()
    r7_transport_inputs(c, s)
    r7_check_fault(c, gamma)
    modes=r7_fixed_battery_modes(c.data, fixed_battery_modes)
    isfinite(budget_sec)&&0<=budget_sec<=600 || error("逐管调度预算须在0至600秒")
    stop=start+budget_sec
    r=Dict{String,Any}(
        "schema"=>"r7-transport-result-v1",
        "version"=>s["version"],
        "run_id"=>"r7-transport-"*string(uuid4()),
        "case_sha256"=>c.sha256,
        "spec_sha256"=>r7_digest(s),
        "fault"=>Int.(gamma),
        "objective_kind"=>"expected_unserved_energy_MWh",
        "status"=>"budget_exhausted",
        "termination_status"=>"NOT_RUN",
        "utc"=>string(now(UTC)),
        "julia_version"=>string(VERSION),
        "requested_budget_sec"=>Float64(budget_sec),
        "optimizer_request"=>sprint(show, optimizer),
        "source_hashes_at_solve"=>r7_transport_science_hashes(),
    )
    fixed_z===nothing || (r["fixed_z"]=Int.(fixed_z))
    modes===nothing || (r["fixed_battery_modes"]=Dict(k=>r7_pack(a) for (k, a) in modes))
    if time()<stop
        try
            b=build_r7_transport_recovery(
                c,
                gamma,
                s;
                optimizer,
                fixed_z,
                fixed_battery_modes = modes,
                deadline = stop,
            )
            r["model_class"]=b.model_class
            r["formula_ids"]=sort(collect(keys(b.constraints)))
            r["replaced_formulas"]=b.replaced_formulas
            set_silent(b.model)
            if time()<stop
                set_time_limit_sec(b.model, stop-time())
                optimize!(b.model)
                t=termination_status(b.model)
                r["termination_status"]=string(t)
                r["raw_status"]=raw_status(b.model)
                r["primal_status"]=string(primal_status(b.model))
                r["solver"]=solver_name(b.model)
                r["status"]=t==MOI.OPTIMAL ? "solver_optimal" :
                            t==MOI.INFEASIBLE ? "infeasible_certified" :
                            t==MOI.TIME_LIMIT ?
                            (
                    has_values(b.model) ? "time_limit_with_incumbent" : "time_limit_no_solution"
                ) : "solver_"*lowercase(string(t))
                if has_values(b.model)&&primal_status(b.model) in
                                        (MOI.FEASIBLE_POINT, MOI.NEARLY_FEASIBLE_POINT)
                    r["values"]=Dict(k=>r7_pack(value.(v)) for (k, v) in b.variables)
                    r["thermal_values"]=Dict(
                        k=>r7_pack(value.(v)) for (k, v) in b.thermal_variables
                    )
                    r["solver_objective_MWh"]=objective_value(b.model)
                end
                try
                    lb=objective_bound(b.model)
                    isfinite(lb)&&(r["lower_bound_MWh"]=lb)
                catch err
                    r["bound_unavailable"]=sprint(showerror, err)
                end
            end
        catch err
            r["error"]=sprint(showerror, err)
            r["status"]=occursin("thermal_build_deadline", r["error"]) ? "budget_exhausted" :
                        occursin("licen", lowercase(r["error"])) ? "license_unavailable" :
                        "solver_or_build_error"
        end
    end
    r["validation"]=validate_r7_transport_recovery(c, s, r)
    r["elapsed_sec"]=time()-start
    r
end

"""
    r7_reconstruct_battery_cycles(case, spec, result)

对原和式域、已通过采用模型检查的逐管恢复值作显式理想电池重构（R7-B2）。
仅当每个被移除循环的双效率均为1时允许：等量减少充放功率，保持净注入、全部能量
轨迹、热状态、失供及其目标不变，再独立核验新互斥域。非理想效率或负原值直接拒绝。
返回新的case/spec/result，不求解、不覆盖父记录、不继承求解器最优界；这不认证完整物理模型。
"""
function r7_reconstruct_battery_cycles(c::R7RecoveryCase, s, parent)
    started=time()
    r7_battery_rule(c.data)=="paper_sum_bound" || error("重构入口只接受原和式域")
    validate_r7_transport_recovery(c, s, parent)["model_pass"] || error("父逐管调度未通过采用模型")
    v=deepcopy(parent["values"])
    ch, dis=(r7_unpack(v, k) for k in ("P_ch", "P_dis"))
    b=zeros(size(ch))
    rows=Dict{String,Any}[]
    for (g, dev) in enumerate(c.data["devices"])
        dev["kind"]=="BES" || continue
        for t in 1:c.data["periods"], w in eachindex(c.data["probabilities"])
            effect=r7_battery_cycle_effect(
                ch[g, t, w],
                dis[g, t, w],
                dev["eta_ch"],
                dev["eta_dis"],
                c.data["dt_h"],
            )
            effect.removed_cycle_MW>0 &&
                !(dev["eta_ch"]==dev["eta_dis"]==1) &&
                error("非理想效率不能保持原能量轨迹，不作静默修复")
            push!(
                rows,
                Dict(
                    "device"=>dev["id"],
                    "t"=>t,
                    "scenario"=>w,
                    "removed_cycle_MW"=>effect.removed_cycle_MW,
                    "energy_increment_MWh"=>effect.energy_increment_MWh,
                ),
            )
            ch[g, t, w]=effect.charge_MW
            dis[g, t, w]=effect.discharge_MW
            b[g, t, w]=effect.charge_MW>0 ? 1.0 : 0.0
        end
    end
    v["P_ch"], v["P_dis"], v["b_BES"]=r7_pack(ch), r7_pack(dis), r7_pack(b)
    derived=with_r7_battery_rule(c, "per_period_exclusive_v1")
    spec=deepcopy(s)
    spec["case_sha256"]=derived.sha256
    r=Dict{String,Any}(
        "schema"=>"r7-transport-result-v1",
        "version"=>spec["version"],
        "run_id"=>"r7-battery-reconstruction-"*string(uuid4()),
        "case_sha256"=>derived.sha256,
        "spec_sha256"=>r7_digest(spec),
        "fault"=>deepcopy(parent["fault"]),
        "objective_kind"=>"expected_unserved_energy_MWh",
        "status"=>"algebraic_reconstruction",
        "termination_status"=>"NOT_OPTIMIZED",
        "reconstruction_version"=>"r7_ideal_cycle_reconstruction_v1",
        "parent_run_id"=>parent["run_id"],
        "parent_case_sha256"=>c.sha256,
        "parent_spec_sha256"=>r7_digest(s),
        "parent_result_sha256"=>r7_digest(parent),
        "solver_objective_MWh"=>parent["solver_objective_MWh"],
        "bound_unavailable"=>"no optimizer invoked; parent bound not inherited",
        "values"=>v,
        "thermal_values"=>deepcopy(parent["thermal_values"]),
        "reconstruction_rows"=>rows,
        "optimized_again"=>false,
        "source_hashes_at_solve"=>r7_transport_science_hashes(),
        "utc"=>string(now(UTC)),
        "julia_version"=>string(VERSION),
    )
    haskey(parent, "fixed_z") && (r["fixed_z"]=deepcopy(parent["fixed_z"]))
    r["validation"]=validate_r7_transport_recovery(derived, spec, r)
    r["elapsed_sec"]=time()-started
    (; case = derived, spec, result = r)
end
