function r4_trading_ledger(c, values)
    d=c.data
    dt=d["dt_h"]
    physical=r4_ledger(c, values)
    costs=[physical["actors"][i]["prepayment_cost"] for i in 2:3]
    retail=zeros(2)
    fees=zeros(2)
    contracts=Dict{String,Any}[]
    for carrier in ("P", "H"), t in 1:d["T"]
        q=values[carrier*"_peer"][t]
        for (j, i) in enumerate(2:3)
            buy=values[carrier*"_buy"][i][t]
            sell=values[carrier*"_sell"][i][t]
            exportq=i==2 ? q : -q
            retail[j]+=dt*(
                d["settlement"][carrier*"_buy"]*buy-d["settlement"][carrier*"_sell"]*sell
            )
            fees[j]+=dt*d["settlement"]["fee"]*max(exportq, 0.0)
            push!(
                contracts,
                Dict(
                    "actor"=>d["actors"][i]["id"],
                    "carrier"=>carrier,
                    "t"=>t,
                    "peer_export_MW"=>exportq,
                    "retail_buy_MW"=>buy,
                    "retail_sell_MW"=>sell,
                ),
            )
        end
    end
    u=.-costs .- retail .- fees
    return Dict(
        "resource_cost"=>costs,
        "retail_cost"=>retail,
        "service_fee"=>fees,
        "utility_before_peer_transfer"=>u,
        "aggregator_cost"=>-sum(u),
        "operator_income"=>sum(retail)+sum(fees),
        "contracts"=>contracts,
    )
end

function r4_trading_incumbent(c, locals)
    length(locals)==2 && sort([x["actor"] for x in locals])==[2, 3] || error("必须有两个不同的AG0计划")
    v=Dict{String,Any}()
    T=c.data["T"]
    for key in R4_CONTROL_KEYS
        v[key]=[zeros(key=="E" ? T+1 : T) for _ in 1:3]
        for r in locals
            i=r["actor"]
            v[key][i]=copy(r["values"][key][i])
        end
    end
    b=findfirst(i->c.data["actors"][i]["BS_power_max"]>0, 2:3)
    battery=b===nothing ? nothing : (2:3)[b]
    v["z"]=battery===nothing ? zeros(T) :
           copy(only(filter(x->x["actor"]==battery, locals))["values"]["z"])
    for carrier in ("P", "H")
        v[carrier*"_peer"]=zeros(T)
        v[carrier*"_peer_abs"]=zeros(T)
        for side in ("buy", "sell")
            key=carrier*"_"*side
            v[key]=[zeros(T) for _ in 1:3]
            for r in locals
                v[key][r["actor"]]=copy(r["values"][key])
            end
        end
    end
    return Dict{String,Any}(
        "stage"=>"trading",
        "spec"=>r4_spec(R4Spec(), c),
        "input_sha256"=>c.sha256,
        "values"=>v,
        "solver_objective"=>r4_trading_ledger(c, v)["aggregator_cost"],
        "objective_origin"=>"independent_incumbent_recomputed_not_solver",
        "status"=>"embedded_independent_incumbent",
        "cost_optimization_complete"=>false,
    )
end

function r4_tspa_frozen(trading)
    return [
        Dict("actor"=>i, "values"=>trading["values"], "role"=>"frozen_trading_controls") for
        i in 2:3
    ]
end

function r4_tspa_economics(c, r)
    incumbent=r4_trading_incumbent(c, r["parents"]["independent"]["local_stages"])
    d0=r4_trading_ledger(c, incumbent["values"])["utility_before_peer_transfer"]
    trading=r["trading_selected"]
    tl=r4_trading_ledger(c, trading["values"])
    weights=r4_bargaining_weights(c; rule = Symbol(r["tspa_spec"]["weight_rule"]))["weights"]
    first=r4_nash_allocation(tl["utility_before_peer_transfer"], d0, weights[2:3])
    first["validation"]=validate_r4_allocation(first)
    out=Dict{String,Any}(
        "trading_ledger"=>tl,
        "stage1"=>first,
        "stage1_disagreement"=>d0,
        "stage2"=>Dict{String,Any}[],
        "coalition_core_certified"=>false,
    )
    first["validation"]["allocation_pass"] || return out
    elastic=r["elastic_network"]
    haskey(elastic, "values") || return out
    ev=validate_r4_elastic(c, elastic; frozen = r4_tspa_frozen(trading))
    ev["relaxed_model_pass"] || return out
    central=r["parents"]["central"]
    cv=validate_r4_solution(c, central)
    cv["model_pass"] && cv["electric_original_pass"] || return out
    lc=r4_ledger(c, central["values"])
    ln=r4_ledger(c, elastic["values"])
    u=[-x["prepayment_cost"] for x in lc["actors"]]
    dso=tl["operator_income"]-ln["actors"][1]["prepayment_cost"]
    for included in (false, true)
        charge=included ? ev["penalty_cost"] : 0.0
        d=[dso-charge; first["utility_after"]]
        allocation=r4_nash_allocation(u, d, weights)
        val=validate_r4_allocation(allocation)
        row=Dict{String,Any}(
            "variant"=>included ? "penalty_included" : "penalty_excluded",
            "allocation"=>allocation,
            "validation"=>val,
            "resource_surplus"=>ln["operating_cost"]-lc["operating_cost"],
            "included_penalty"=>charge,
            "penalty_cost"=>ev["penalty_cost"],
            "disagreement_physical_pass"=>ev["original_physical_pass"],
            "central_physical_pass"=>true,
            "model_total_welfare_premise"=>allocation["surplus"]>=0,
            "resource_surplus_is_feasible_saving"=>ev["original_physical_pass"],
        )
        if haskey(allocation, "utility_after")
            row["aggregator_gain_vs_original_independent"]=allocation["utility_after"][2:3] .- d0
        end
        push!(out["stage2"], row)
    end
    return out
end

"""
    solve_r4_tspa(case; independent, central, optimizer, spec=R4TSPASpec(),
                  electric=:socp, enumerate_battery=false, budget_sec=600)

求解忽略网络的聚合商交易、严格冻结网络及节点弹性网络，再计算两阶段转移。
independent提供同输入两个AG0局部计划；central是已有同输入合作计划，不作为交易初值。
AG0可以嵌入为零P2P的已知可行候选；若其独立重算费用更低，显式保留该候选与原求解记录。
全部新建模/枚举共享墙钟预算，交易至多40%、严格网络至多30%、弹性阶段使用剩余预算。
trading_run可显式复用已验收交易候选以隔离罚系数因素，历史求解耗时单列，不重复计入本次预算。
原式(4-95)–(4-102)的项目采用：仅节点平衡松弛，罚项进/不进分歧效用并列。
松弛有解、单阶段分配、最终合作计划物理通过和所有子联盟稳定是不同结论。
"""
function solve_r4_tspa(
    c::R4Case;
    independent,
    central,
    optimizer,
    spec = R4TSPASpec(),
    electric = :socp,
    enumerate_battery = false,
    budget_sec = 600.0,
    trading_run = nothing,
)
    isfinite(budget_sec) && budget_sec>0 || error("预算须为有限正数")
    enumerate_battery && c.data["T"]>10 && error("枚举仅用于小系统")
    start=time()
    deadline=start+budget_sec
    hashes=r4_science_hashes()
    for parent in (independent, central)
        parent["input_sha256"]==c.sha256 || error("父输入不一致")
    end
    locals=independent["local_stages"]
    length(locals)==2 && all(validate_r4_solution(c, x)["model_pass"] for x in locals) ||
        error("AG0局部计划不合格")
    ns=R4Spec(operation = :independent, electric = electric)
    r=Dict{String,Any}(
        "schema"=>"r4-tspa-run-v1",
        "origin"=>"synthetic",
        "input_sha256"=>c.sha256,
        "tspa_spec"=>r4_tspa_spec(spec),
        "electric"=>String(electric),
        "budget_sec"=>Float64(budget_sec),
        "source_hashes_at_solve"=>hashes,
        "parents"=>Dict("independent"=>deepcopy(independent), "central"=>deepcopy(central)),
    )
    if trading_run===nothing
        trading=r4_solve_stage(
            c,
            ns,
            optimizer,
            min(deadline, start+0.4budget_sec);
            stage = :trading,
            enumerate_battery,
        )
        r["trading_origin"]="solved_this_run"
    else
        validate_r4_trading(c, trading_run)["model_pass"] || error("复用交易未通过验收")
        trading=deepcopy(trading_run)
        r["trading_origin"]="explicit_saved_candidate"
        r["trading_parent_sha256"]=bytes2hex(sha256(r4_text(trading_run)))
        r["historical_trading_elapsed_sec"]=get(trading_run, "elapsed_sec", 0.0)
    end
    trading["objective_type"]="aggregator_resource_plus_retail_and_service"
    trading["validation"]=validate_r4_trading(c, trading)
    incumbent=r4_trading_incumbent(c, locals)
    incumbent["validation"]=validate_r4_trading(c, incumbent)
    incumbent["validation"]["model_pass"] || error("已知AG0嵌入未通过独立验收")
    choose_solver=trading["validation"]["model_pass"] &&
                  r4_trading_ledger(c, trading["values"])["aggregator_cost"]<=incumbent["solver_objective"]
    r["trading_solver"]=trading
    r["trading_selected"]=deepcopy(choose_solver ? trading : incumbent)
    r["selection"]=choose_solver ? "solver_candidate" : "known_independent_incumbent"
    r["selection_rule"]="lowest_independently_recomputed_aggregator_cost_among_valid_candidates"
    frozen=r4_tspa_frozen(r["trading_selected"])
    strict=r4_solve_stage(
        c,
        ns,
        optimizer,
        min(deadline, time()+0.3budget_sec);
        stage = :network,
        frozen,
        enumerate_battery,
    )
    strict["local_stages"]=frozen
    strict["objective_type"]="physical_resource_cost_with_frozen_aggregators"
    strict["validation"]=validate_r4_solution(c, strict)
    r["strict_network"]=strict
    elastic=r4_solve_stage(
        c,
        ns,
        optimizer,
        deadline;
        stage = :network,
        frozen,
        enumerate_battery,
        build_options = (balance_penalty = spec.penalty,),
    )
    elastic["balance_penalty"]=spec.penalty
    elastic["normalization_scales"]=r4_tspa_scales(c)
    elastic["objective_type"]="physical_resource_cost_plus_artificial_penalty"
    elastic["validation"]=validate_r4_elastic(c, elastic; frozen)
    r["elastic_network"]=elastic
    r["economics"]=r4_tspa_economics(c, r)
    r["elapsed_sec"]=time()-start
    hashes==r4_science_hashes() || error("求解期间源码变化，不能封存")
    r["validation"]=validate_r4_tspa(c, r)
    return r
end
