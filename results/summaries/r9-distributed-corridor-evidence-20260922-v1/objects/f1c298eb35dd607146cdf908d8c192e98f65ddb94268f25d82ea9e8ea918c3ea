"""
    solve_r4_reconfiguration(case; optimizer, spec=R4ReconfigurationSpec(),
                            budget_sec=600, modes=nothing,
                            electric_schedule=nothing, heat_open=nothing, heat_direction=nothing)

共享预算内求解集中式电热重构；固定离散计划可由Clarabel求解SOCP，未固定时使用整数求解器。
预算包括建模/求解，不自动切换松弛或原等式版本。保存原始状态、界、实际成本和物理验收；
原始失败保留，独立参考不注入候选。项目R4-N1至N6。
"""
function solve_r4_reconfiguration(
    c::R4Case;
    optimizer,
    spec = R4ReconfigurationSpec(),
    budget_sec = 600.0,
    modes = nothing,
    electric_schedule = nothing,
    heat_open = nothing,
    heat_direction = nothing,
)
    haskey(c.data, "network_control") || error("缺失重构输入")
    isfinite(budget_sec) && budget_sec>0 || error("预算错误")
    start=time()
    hashes=r4_science_hashes()
    switching=(; policy = spec.policy, electric_schedule, heat_open, heat_direction)
    r=r4_solve_stage(
        c,
        R4Spec(electric = spec.electric),
        optimizer,
        start+budget_sec;
        build_options = (; switching, modes),
    )
    r["spec"]["version"]="r4_reconfiguration_checked_v1"
    r["reconfiguration"]=Dict{String,Any}("policy"=>String(spec.policy))
    for (key, value) in (
        ("electric_schedule", electric_schedule),
        ("heat_open", heat_open),
        ("heat_direction", heat_direction),
    )
        value===nothing ||
            (r["reconfiguration"][key]=value isa AbstractMatrix ? r4_rows(value) : value)
    end
    r["source_hashes_at_solve"]=hashes
    r["budget_sec"]=Float64(budget_sec)
    r["validation"]=validate_r4_reconfiguration(c, r)
    if haskey(r, "values")
        r["ledger"]=r4_ledger(c, r["values"])
        r["operating_cost"]=r["ledger"]["operating_cost"]
        r["switching_cost"]=r4_switch_cost(c, r["values"])
        r["cost_optimization_complete"] &= r["validation"]["model_pass"]
    end
    hashes==r4_science_hashes() || error("重构求解期间源码变化")
    r["elapsed_sec"]=time()-start
    return r
end

"""
    r4_network_states(case, carrier)

用独立图遍历枚举物理边的全部连通树，carrier为electric或heat。
顺序按二进制整数、第一物理边最低位；不根据费用筛选，热流方向不作为连通方向。
"""
function r4_network_states(c::R4Case, carrier::Symbol)
    carrier in (:electric, :heat) || error("网络类别错误")
    edges=carrier==:electric ? c.data["electric"]["edges"] : c.data["heat"]["pipes"][1:3]
    return [
        on for on in ([((k>>(p-1))&1) for p in eachindex(edges)] for k in 0:(2^length(edges)-1)) if
        r4_is_tree(edges, on)
    ]
end

"""
    enumerate_r4_reconfiguration(case; optimizer, budget_sec=600)

单时段合成解析对照：枚举全部电树、日热树、接通热管方向和电池模式后求连续SOCP。
只支持T=1，三边时为72个凸问题；这是完整单时段参考，不冒充四时段全枚举。
共享预算，缺失/失败子问题使全问题界失效。返回原始逐项结果与覆盖/最好模型/物理候选。
"""
function enumerate_r4_reconfiguration(c::R4Case; optimizer, budget_sec = 600.0)
    c.data["T"]==1 || error("本穷举参照只支持单时段")
    isfinite(budget_sec)&&budget_sec>0 || error("预算错误")
    start=time()
    deadline=start+budget_sec
    hashes=r4_science_hashes()
    rows=Dict{String,Any}[]
    for e in r4_network_states(c, :electric),
        h in r4_network_states(c, :heat),
        signs in 0:3,
        mode in r4_battery_patterns(c)

        dir=zeros(Int, 3, 1)
        active=findall(==(1), h)
        for (i, p) in enumerate(active)
            dir[p, 1]=(signs>>(i-1))&1
        end
        entry=Dict{String,Any}(
            "electric"=>e,
            "heat"=>h,
            "directions"=>r4_rows(dir),
            "mode"=>mode,
            "status"=>"not_run_budget",
        )
        push!(rows, entry)
        time()>=deadline && continue
        raw=solve_r4_reconfiguration(
            c;
            optimizer,
            budget_sec = deadline-time(),
            modes = mode,
            electric_schedule = reshape(e, :, 1),
            heat_open = h,
            heat_direction = dir,
        )
        entry["raw"]=raw
        entry["status"]=raw["status"]
    end
    best=0
    physical=0
    cost=Inf
    physicalcost=Inf
    bounds=Float64[]
    bounded=true
    for (i, x) in enumerate(rows)
        if !haskey(x, "raw")
            bounded=false
            continue
        end
        r=x["raw"]
        if r["status"]!="infeasible_certified"
            if isfinite(get(r, "objective_bound", NaN))
                push!(bounds, r["objective_bound"])
            else
                bounded=false
            end
        end
        if r["validation"]["model_pass"]
            if r["operating_cost"]<cost
                best=i
                cost=r["operating_cost"]
            end
            if r["validation"]["electric_original_pass"] && r["operating_cost"]<physicalcost
                physical=i
                physicalcost=r["operating_cost"]
            end
        end
    end
    lower=bounded && !isempty(bounds) ? minimum(bounds) : NaN
    gap=isfinite(lower)&&isfinite(cost) ? abs(cost-lower)/max(1, abs(cost)) : NaN
    return Dict(
        "schema"=>"r4-network-enumeration-v1",
        "input_sha256"=>c.sha256,
        "records"=>rows,
        "best_model_index"=>best,
        "best_physical_index"=>physical,
        "best_model_cost"=>cost,
        "best_physical_cost"=>physicalcost,
        "objective_bound"=>lower,
        "relative_gap"=>gap,
        "certificate_A2"=>isfinite(gap)&&gap<=1e-4,
        "source_hashes_at_solve"=>hashes,
        "budget_sec"=>Float64(budget_sec),
        "elapsed_sec"=>time()-start,
    )
end
