"""
    r4_battery_patterns(case)

枚举本批唯一电池的全部逐时互斥状态，按二进制整数递增、第一时段为最低位。
1表示可充电、0表示可放电，两者都允许闲置；相同物理调度的重复模式保留。
仅支持1至10时段的小系统；无电池时只返回全零模式，不制造无意义的重复选择。
"""
function r4_battery_patterns(c::R4Case)
    T=c.data["T"]
    1<=T<=10 || error("状态穷举仅限1至10时段")
    has=any(x["BS_power_max"]>0 for x in c.data["actors"])
    return [[(n>>(t-1))&1 for t in 1:T] for n in 0:(has ? 2^T-1 : 0)]
end

"""
    reconstruct_r4_cost(case, raw_candidate)

在保存值副本中把不满意度上图变量取到理论值，重算采用模型目标，不调用求解器。
设备、负荷、网络、储能及合同逐值不变；原目标/验收另存，实际费用必须严格相同。
只支持central/trading候选，不修复共识或原电网关系，不产生新的最优性证书。
返回candidate、原验收、未变控制哈希和重算目标来源；项目式R4-E1及测试R4 discrete audit。
"""
function reconstruct_r4_cost(c::R4Case, raw)
    raw["input_sha256"]==c.sha256 || error("输入不匹配")
    stage=get(raw, "stage", "")
    stage in ("central", "trading") && haskey(raw, "values") || error("成本重构范围错误")
    check=stage=="central" ? validate_r4_solution : validate_r4_trading
    ledger=stage=="central" ? r4_ledger : r4_trading_ledger
    costkey=stage=="central" ? "operating_cost" : "aggregator_cost"
    candidate=deepcopy(raw)
    s=candidate["values"]
    for i in 1:3, carrier in ("P", "H"), t in 1:c.data["T"]
        a=c.data["actors"][i]
        scale=get(c.data, "preference_model", "")=="explicit_reference_v1" ? a["sat_"*carrier] : 1.0
        # w只参与正费用项与平方下界；其余物理控制不变。
        s["w_"*carrier][i][t]=a["sat_"*carrier]>0 ?
                              scale*(r4_preferred_demand(a, carrier, t)-s[carrier*"_D"][i][t])^2 :
                              0.0
    end
    keys_control=[k for k in keys(s) if !(k in ("w_P", "w_H"))]
    all(isequal(s[k], raw["values"][k]) for k in keys_control) || error("重构改变控制")
    cost=ledger(c, s)[costkey]
    isequal(cost, ledger(c, raw["values"])[costkey]) || error("实际费用改变")
    candidate["raw_solver_objective"]=raw["solver_objective"]
    candidate["solver_objective"]=cost
    candidate["operating_cost"]=cost
    candidate["objective_origin"]="analytical_epigraph_reconstruction_not_solver_output"
    candidate["status"]="postprocessed_candidate"
    candidate["cost_optimization_complete"]=false
    candidate["validation"]=check(c, candidate)
    return Dict(
        "candidate"=>candidate,
        "raw_validation"=>check(c, raw),
        "control_sha256"=>bytes2hex(sha256(r4_text(Dict(k=>s[k] for k in keys_control)))),
        "actual_cost_unchanged"=>true,
        "new_solver_certificate"=>false,
    )
end

"""
    solve_r4_discrete(case; optimizer, method=:distributed, budget_sec=600,
                      distributed_spec=R4DistributedSpec())

在共享墙钟预算内依次求解全部电池模式，保存每项原始解和显式成本重构。
method为distributed或central_enumeration，二者完全独立；分布法不读取集中参考。
按实际费用分别保留采用模型合格与原电网合格的最低费用候选，平局取最早模式。
枚举完成、模式内收敛、原物理通过、全模式费用界分别报告；不将分布块界拼成系统界。
对应项目式R4-E2/E3；构造、求解、核算共用budget_sec，不写文件。
"""
function solve_r4_discrete(
    c::R4Case;
    optimizer,
    method = :distributed,
    budget_sec = 600.0,
    distributed_spec = R4DistributedSpec(),
)
    method in (:distributed, :central_enumeration) || error("未知穷举方法")
    isfinite(budget_sec)&&budget_sec>0 || error("预算错误")
    start=time()
    deadline=start+budget_sec
    hashes=r4_science_hashes()
    patterns=r4_battery_patterns(c)
    records=Dict{String,Any}[]
    for (index, modes) in enumerate(patterns)
        entry=Dict{String,Any}("index"=>index, "modes"=>modes, "status"=>"not_run_budget")
        push!(records, entry)
        time()>=deadline && continue
        if method==:distributed
            raw=solve_r4_distributed(
                c;
                optimizer,
                modes,
                spec = distributed_spec,
                budget_sec = deadline-time(),
            )
            entry["raw"]=raw
            entry["status"]=raw["status"]
            haskey(raw, "candidate") &&
                (entry["reconstruction"]=reconstruct_r4_cost(c, raw["candidate"]))
        else
            raw=r4_solve_stage(c, R4Spec(), optimizer, deadline; build_options = (; modes))
            raw["validation"]=validate_r4_solution(c, raw)
            entry["raw"]=raw
            entry["status"]=raw["status"]
            haskey(raw, "values") && (entry["reconstruction"]=reconstruct_r4_cost(c, raw))
        end
    end
    result=Dict{String,Any}(
        "schema"=>"r4-discrete-run-v1",
        "input_sha256"=>c.sha256,
        "method"=>String(method),
        "algorithm"=>"r4_finite_mode_enumeration_v1",
        "records"=>records,
        "source_hashes_at_solve"=>hashes,
        "budget_sec"=>Float64(budget_sec),
        "elapsed_sec"=>time()-start,
        "pattern_count"=>length(patterns),
        "options"=>r4_distributed_options(distributed_spec),
    )
    result["validation"]=validate_r4_discrete(c, result)
    result["status"]=result["validation"]["all_modes_attempted"] ? "enumeration_finished" :
                     "enumeration_budget_exhausted"
    hashes==r4_science_hashes() || error("枚举期间科学源码变化")
    result["elapsed_sec"]=time()-start
    return result
end
