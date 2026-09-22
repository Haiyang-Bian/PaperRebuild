"""R9-DC3：保留运营商网络变量，逐主体复制实际控制后独立验算；不平均消息或重新求解。"""
function r9_distributed_candidate(c::R9TradingCase, agents, operator)
    a, g=c.data["actors"], c.data["devices"]
    length(agents)==length(a)-1 && Set(r["actor"] for r in agents)==Set(2:length(a)) ||
        error("分布主体缺失或重复")
    operator["actor"]==1 && operator["input_sha256"]==c.sha256 || error("运营商身份错误")
    all(r->r["input_sha256"]==c.sha256, agents) || error("主体输入不同")
    s=deepcopy(operator["values"])
    pop!(s, "boundary", nothing)
    for r in agents
        i=r["actor"]
        for key in ("P_D", "H_D", "w_P", "w_H")
            s[key][i]=copy(r["values"][key][i])
        end
        for j in eachindex(g)
            g[j]["owner"]==i || continue
            for key in ("P_gen", "P_cons", "H_gen", "H_cons", "E", "z_storage")
                s[key][j]=copy(r["values"][key][j])
            end
        end
    end
    candidate=Dict{String,Any}(
        "input_sha256"=>c.sha256,
        "stage"=>"central",
        "operation"=>"central",
        "actor"=>0,
        "electric"=>"socp",
        "values"=>s,
        "status"=>"assembled_distributed_candidate",
        "source_role"=>"assembled_controls_not_a_central_solver_run",
        "objective_kind"=>"sum_of_unaugmented_block_objectives",
        "solver_objective"=>operator["cost"]+sum(r["cost"] for r in agents),
        "cost_optimization_complete"=>false,
    )
    candidate["validation"]=validate_r9_trading_solution(c, candidate)
    candidate["operating_cost_CNY"]=r9_trading_costs(c, s).total
    candidate
end

"""独立重算块的未增广上图目标；实际二次不满意度另由合并验证器核算。"""
function r9_distributed_block_cost(c, b)
    s=b["values"]
    i=b["actor"]
    d=c.data
    localcost=r9_trading_costs(c, s; actor = i)
    cost=sum(localcost.resource)+d["dt_h"]*sum(s["w_P"][i]+s["w_H"][i])
    if i==1
        cost+=d["dt_h"]*sum(d["grid_price"] .* s["P_grid"])+r9_switching_cost(c, s)
    end
    cost
end

"""
    validate_r9_distributed(case, result)

R9-DC5：从每轮各块原变量重建消息、成本、乘子递推与增广目标，不读取JuMP表达式。
重新合并并回代原采用方程，核对最好模型/原电网候选身份和固定模式；拒绝把不一致消息平均。
分别返回记录、A4、采用A1及原电网检查。求解器子块OPTIMAL不是全局社会费用证书，
整数启发式也不因残差较小而获得凸收敛保证。没有完成轮次的失败记录仍可正确保存。
"""
function validate_r9_distributed(c::R9TradingCase, r)
    r["schema"]=="r9-distributed-run-v1" && r["input_sha256"]==c.sha256 ||
        error("分布输入/版本不符")
    r["model_version"]==r9_trading_version(c) && r["origin"]==c.data["origin"] ||
        error("采用模型身份改变")
    spec=R9DistributedSpec(;
        algorithm = Symbol(r["algorithm"]),
        rho = r["rho"],
        max_iterations = r["max_iterations"],
    )
    r["consensus_tolerance"]==1e-4 && r["initialization"]=="zero_messages_and_scaled_duals" ||
        error("停止门槛或初值改变")
    !r["cost_optimization_complete"] &&
    !r["central_solution_injected"] &&
    !r["full_thermal_physics_certified"] || error("扩大了分布验收范围")
    modes=haskey(r, "fixed_modes") ? Dict(k=>r4_matrix(v) for (k, v) in r["fixed_modes"]) : nothing
    r9_distributed_modes(c, modes, spec)
    box=r9_boundary_contract(c)
    C=r9_distributed_cost_scale(c)
    box.scale==r["boundary_scale"] && C==r["cost_scale"] || error("冻结归一化改变")
    all(x->isfinite(x)&&x>=0, (r["elapsed_sec"], r["budget_sec"])) && 0<r["budget_sec"]<=600 ||
        error("预算记录错误")
    r["budget_overrun"]==(r["elapsed_sec"]>r["budget_sec"]) || error("预算超出被隐藏")
    function same(a, b, label)
        size(a)==size(b) &&
        all(isfinite, a) &&
        all(isfinite, b) &&
        maximum(abs, a-b; init = 0.0)<=1e-10 || error(label)
    end
    near(a, b, label) =
        isfinite(a)&&isfinite(b)&&abs(a-b)<=1e-9*max(1, abs(a), abs(b)) || error(label)
    zold=zeros(size(box.lower))
    uold=zeros(size(zold))
    bestmodel=0
    bestphysical=0
    bestcost=Inf
    physicalcost=Inf
    lastmodel=false
    lastphysical=false
    a4=false
    lastcost=NaN
    lastelapsed=0.0
    length(r["trace"])<=spec.max_iterations || error("迭代超出冻结上限")
    for (k, row) in enumerate(r["trace"])
        row["iteration"]==k || error("迭代顺序改变")
        isfinite(row["elapsed_sec"]) && lastelapsed<=row["elapsed_sec"]<=r["elapsed_sec"] ||
            error("迭代时间顺序错误")
        lastelapsed=row["elapsed_sec"]
        agents=row["agents"]
        operator=row["operator"]
        [b["actor"] for b in agents]==collect(2:length(c.data["actors"])) || error("主体顺序或完整性改变")
        allblocks=[operator; agents]
        for b in allblocks
            b["input_sha256"]==c.sha256 &&
            b["status"]=="solved" &&
            b["termination"]=="OPTIMAL" &&
            b["primal_status"] in ("FEASIBLE_POINT", "NEARLY_FEASIBLE_POINT") ||
                error("未完成块被计为有效迭代")
            spec.algorithm==:r9_boundary_admm_fixed_v1 &&
                !b["convex_fixed_mode"] &&
                error("连续声明含整数")
            isfinite(b["elapsed_sec"]) &&
            b["elapsed_sec"]>=0 &&
            0<=b["allocated_budget_sec"]<=r["budget_sec"] || error("块预算被重置")
            near(r9_distributed_block_cost(c, b), b["cost"], "块原目标与控制不符")
            if haskey(b, "augmented_bound")
                obj, lb=b["augmented_objective"], b["augmented_bound"]
                near(
                    max(0.0, obj-lb)/max(1.0, abs(obj)),
                    b["augmented_relative_gap"],
                    "增广界间隙改变",
                )
                near(
                    max(0.0, lb-obj)/max(1.0, abs(obj)),
                    b["augmented_bound_excess"],
                    "增广界方向改变",
                )
            end
            if modes!==nothing
                for (key, m) in modes
                    haskey(b["values"], key) || continue
                    for i in axes(m, 1), t in axes(m, 2)
                        if key=="z_storage"
                            g=c.data["devices"][i]
                            g["kind"] in ("BS", "HS") && g["owner"]==b["actor"] || continue
                        end
                        abs(b["values"][key][i][t]-m[i, t])<=1e-6 || error("冻结模式与块控制不符")
                    end
                end
            end
        end
        for b in agents
            same(
                r9_trading_boundary(c, b["values"]; actor = b["actor"]),
                r4_matrix(b["message"]),
                "主体消息不是实际边界",
            )
        end
        same(
            r4_matrix(operator["values"]["boundary"]),
            r4_matrix(operator["message"]),
            "运营商副本身份改变",
        )
        raw=vcat((r4_matrix(b["message"]) for b in agents)...)
        x=raw ./ reshape(box.scale, :, 1)
        z=r4_matrix(operator["message"]) ./ reshape(box.scale, :, 1)
        u=r4_matrix(row["u"])
        same(x, r4_matrix(row["x"]), "主体归一化改变")
        same(z, r4_matrix(row["z"]), "运营商归一化改变")
        same(u, uold+x-z, "缩放乘子递推错误")
        near(maximum(abs, x-z), row["primal"], "原始残差改变")
        near(spec.rho*maximum(abs, z-zold), row["dual"], "对偶残差改变")
        for b in agents
            rows=(4(b["actor"]-2)+1):(4(b["actor"]-1))
            aug=b["cost"]/C+spec.rho/2*sum(abs2, x[rows, :]-zold[rows, :]+uold[rows, :])
            near(aug, b["augmented_objective"], "主体增广目标或符号错误")
        end
        aug=operator["cost"]/C+spec.rho/2*sum(abs2, z-x-uold)
        near(aug, operator["augmented_objective"], "运营商增广目标或符号错误")
        candidate=r9_distributed_candidate(c, agents, operator)
        v=candidate["validation"]
        isequal(r9_trading_summary(v), row["candidate_validation"]) || error("合并A1判定被改写")
        near(candidate["operating_cost_CNY"], row["operating_cost_CNY"], "合并实际费用错误")
        lastmodel=v["model_pass"]
        lastphysical=lastmodel&&v["electric_original_pass"]
        lastcost=candidate["operating_cost_CNY"]
        if lastmodel && lastcost<bestcost
            bestmodel=k
            bestcost=lastcost
        end
        if lastphysical && lastcost<physicalcost
            bestphysical=k
            physicalcost=lastcost
        end
        a4=row["primal"]<=1e-4 && row["dual"]<=1e-4
        a4 && lastmodel && k<length(r["trace"]) && error("停止后仍伪装正常外层更新")
        zold=z
        uold=u
    end
    bestmodel==r["best_model_iteration"] && bestphysical==r["best_physical_iteration"] ||
        error("最佳候选被覆盖或改选")
    statuses=(
        "consensus_converged",
        "iteration_limit",
        "time_limit",
        "time_limit_with_candidate",
        "infeasible_certified",
        "infeasible_or_unbounded",
        "solver_failure",
        "license_missing",
        "unsupported_solver",
        "solver_error",
        "algorithm_error",
    )
    r["status"] in statuses || error("未知分布停止状态")
    if r["status"]=="consensus_converged"
        a4 && lastmodel || error("共识停止证据不足")
    elseif r["status"]=="iteration_limit"
        length(r["trace"])==spec.max_iterations && !(a4&&lastmodel) || error("迭代上限状态不符")
    end
    if haskey(r, "last_attempt")
        attempt=r["last_attempt"]
        attempt["iteration"]==length(r["trace"])+1 || error("失败试探混入完整迭代")
        failed=haskey(attempt, "operator") ? attempt["operator"] : last(attempt["agents"])
        failed["status"]==r["status"] && failed["status"]!="solved" || error("失败状态未正确传播")
    end
    Dict{String,Any}(
        "record_pass"=>true,
        "consensus_A4_pass"=>a4,
        "last_model_pass"=>lastmodel,
        "last_electric_original_pass"=>lastphysical,
        "best_model_found"=>bestmodel>0,
        "best_physical_found"=>bestphysical>0,
        "best_model_cost_CNY"=>bestmodel>0 ? bestcost : NaN,
        "best_physical_cost_CNY"=>bestphysical>0 ? physicalcost : NaN,
        "last_cost_CNY"=>lastcost,
        "iterations"=>length(r["trace"]),
        "cost_optimization_complete"=>false,
        "full_thermal_physics_certified"=>false,
        "mixed_integer_heuristic"=>spec.algorithm==:r9_boundary_admm_mip_v1,
    )
end
