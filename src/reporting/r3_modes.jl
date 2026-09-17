"""
    solve_r3_reference(case; operation, optimizer=nothing, budget_sec=600)

同一四模式详细物理模型的直接最小费用参考：精确热功率、混合、WMM、电网原等式及κ等式。
CF采用固定流量以消去输运非线性，VF保留变量流量。共享预算包含建模，不承诺全局最优。
返回独立R3运行，绝不作为投影梯度成功；与最小流量改动修正有不同目标。
"""
function solve_r3_reference(c::R2Case; operation, optimizer = nothing, budget_sec = 600.0)
    isfinite(budget_sec) && 0<budget_sec<=600 || throw(ArgumentError("预算须在(0,600]秒"))
    start=r3_clock()
    deadline=start+budget_sec
    function builder()
        r3_is_cf(operation) &&
            return build_r3_subproblem(c, r2_flow_matrix(c); operation, physical = true)
        b=build_r2_model(c; operation)
        r3_add_physics!(c, b)
        return merge(
            b,
            (;
                class = r2_model_class(b.model),
                variant = "r3_cost_reference_v1",
                objective_kind = "operating_cost",
                cost_expression = objective_function(b.model),
                elastic_rows = NamedTuple[],
                flow_schedule = r2_flow_matrix(c),
            ),
        )
    end
    out=Dict{String,Any}(
        "schema"=>"r3-run-v1",
        "algorithm"=>"r3_cost_reference_v1",
        "input_sha256"=>c.sha256,
        "source_hashes_at_solve"=>r2_science_hashes(),
        "operation"=>r3_operation_dict(operation),
        "budget_sec"=>budget_sec,
    )
    out["operation_sha256"]=r3_operation_hash(out["operation"])
    r=r3_solve(c, builder, optimizer; budget_sec, deadline)
    r["stage"]="direct_cost_reference"
    report=validate_r3_solution(c, r)
    r["model_pass"], r["physics_pass"]=report.model_pass, report.physical_pass
    out["stages"]=[r]
    out["final_stage"]=report.physical_pass ? 1 : 0
    out["status"]=report.physical_pass ? "physical_feasible" : "no_verified_physical_solution"
    out["outer_status"]="not_applicable_direct_reference"
    out["outer_converged"]=false
    out["cost_optimization_complete"]=report.physical_pass && r["status"]=="solver_optimal"
    out["elapsed_sec"]=r3_clock()-start
    return out
end

function r3_recovery_rows!(record, c, result)
    haskey(result, "operation") && haskey(c.data, "r3_mechanism") || return
    o=r3_operation_from_dict(result["operation"])
    o.core_periods<c.data["T"] || return
    v=result["values"]
    T=c.data["T"]
    for (p, e) in enumerate(c.data["heat"]["pipes"]), side in ("S", "R")
        # 末端全部有效记忆的入口温度、流量恢复，才能称为相同热状态。
        dt=3600c.data["dt_h"]
        mass=c.data["heat"]["rho_kg_m3"]*e["area_m2"]*e["length_m"]
        cover=ceil(Int, mass/(dt*e["flow_min"]))+1
        for t in max(o.core_periods+1, T-cover):T
            record(
                "R3-terminal-inlet",
                side*string(p),
                t,
                v["tau_"*side*"_in"][p][t]-last(e[side*"_history_K"]),
                "K",
                1e-4;
                scope = "physics",
            )
            record(
                "R3-terminal-flow",
                side*string(p),
                t,
                v["m_pipe"][p][t]-last(e["flow_history"]),
                "kg/s",
                1e-6+1e-6*e["flow_max"];
                scope = "physics",
            )
        end
        replay=r3_mass_replay(c, v, p, T, side)
        record(
            "R3-terminal-replay",
            side*string(p),
            T,
            replay.out-c.data["r3_mechanism"][side*"_steady_out_K"][p],
            "K",
            1e-4;
            scope = "physics",
        )
    end
end

"""
    compare_r3_modes(runs)

读取同一新案例的已保存四模式运行，核对输入与共同参考边界，独立核查物理及恢复状态。
分别返回总/核心/恢复费用、光伏可用/利用/弃电MWh与求解状态。不重新求解；
未通过物理和终端检查的候选不进入公平周期费用排序，不要求四模式严格排序。
"""
function compare_r3_modes(runs)
    isempty(runs) && throw(ArgumentError("没有运行"))
    c=nothing
    rows=Dict{String,Any}[]
    for path in runs
        r=read_r3_run(path)
        isnothing(c) && (c=r.case)
        r.case.data==c.data && r.case.sha256==c.sha256 || throw(ArgumentError("四模式输入不同"))
        result=r.result
        op=result["operation"]
        n=op["core_periods"]
        row=Dict{String,Any}(
            "run_id"=>basename(dirname(abspath(path)))*"/"*r.metadata["run_id"],
            "mode"=>op["mode"],
            "method"=>result["algorithm"],
            "status"=>result["status"],
            "physical_pass"=>validate_r3_solution(c, result).physical_pass,
            "elapsed_sec"=>result["elapsed_sec"],
            "outer_status"=>result["outer_status"],
        )
        i=result["final_stage"]
        if i>0
            s=result["stages"][i]
            v=s["values"]
            costs=[
                c.data["dt_h"]*(
                    c.data["grid_price"][t]*v["P_grid"][t] + sum(
                        g["cost_per_MWh"]*v["P_device"][k][t] for
                        (k, g) in enumerate(c.data["devices"])
                    )
                ) for t in 1:c.data["T"]
            ]
            row["total_cost"]=sum(costs)
            row["core_cost"]=sum(costs[1:n])
            row["recovery_cost"]=sum(costs[(n+1):end])
            pv=findall(g->g["kind"]=="PV", c.data["devices"])
            row["pv_available_MWh"]=c.data["dt_h"]*sum(
                sum(c.data["devices"][k]["availability"]) for k in pv
            )
            row["pv_used_MWh"]=c.data["dt_h"]*sum(sum(v["P_device"][k]) for k in pv)
            row["pv_curtailed_MWh"]=row["pv_available_MWh"]-row["pv_used_MWh"]
            if haskey(s, "solver_bound")
                key=result["algorithm"]=="r3_cost_reference_v1" ? "same_model_bound" :
                    startswith(op["mode"], "CF") ?
                    (s["class"]=="SOCP" ? "relaxation_lower_bound" : "same_model_bound") :
                    "fixed_flow_subproblem_bound"
                row[key]=s["solver_bound"]
                row["reported_gap"]=get(s, "solver_relative_gap", NaN)
                row["gap_scope"]=key
            end
            row["termination"]=get(s, "termination", "unavailable")
            embedded=String[]
            for mode in (:CF_CT, :CF_VT, :VF_CT, :VF_VT)
                target=R3OperationSpec(
                    c;
                    mode,
                    core_periods = n,
                    bounded_return = op["bounded_return"],
                )
                source=r3_operation_from_dict(op)
                (!r3_is_cf(source)&&r3_is_cf(target) || !r3_is_ct(source)&&r3_is_ct(target)) &&
                    continue
                witness=deepcopy(s)
                witness["operation"]=r3_operation_dict(target)
                witness["operation_sha256"]=r3_operation_hash(witness["operation"])
                validate_r3_solution(c, witness).physical_pass ||
                    error("受限模式解无法嵌入自由模式")
                push!(embedded, string(mode))
            end
            row["embedded_modes"]=join(embedded, ",")
        end
        push!(rows, row)
    end
    return rows
end
