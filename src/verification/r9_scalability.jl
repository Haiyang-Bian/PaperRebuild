"""
    audit_r9_aggregator_split(parent, child, mapping)

R9-SC1—SC2：逐字段检查原输入、派生输入及父子映射，不调用优化器。
核对所有网络/设备物理字段不变、负荷可精确聚合、不满意度缩放及整台设备归属。
成功只证明采用构造符合等价性推导的前提，不证明任何实际候选可行、算法收敛或个体收益不变。
"""
function audit_r9_aggregator_split(parent::R9TradingCase, child::R9TradingCase, mapping)
    r9_split_input_identity(parent)
    r9_split_input_identity(child)
    Set(keys(mapping))==Set((
        "schema",
        "rule",
        "multiplier",
        "parent_sha256",
        "child_sha256",
        "parent_for_actor",
        "copy_index",
        "parent_ids",
        "child_ids",
    )) || error("拆分映射字段不完整或多余")
    mapping["schema"]=="r9-aggregator-split-v1" &&
    mapping["rule"]=="equal_demand_scaled_discomfort_indivisible_devices_to_first_child" ||
        error("拆分规则身份错误")
    mapping["parent_sha256"]==parent.sha256 && mapping["child_sha256"]==child.sha256 ||
        error("拆分来源哈希不符")
    k=r9_split_multiplier(mapping["multiplier"])
    p, c=parent.data, child.data
    pa, ca=p["actors"], c["actors"]
    rows=mapping["parent_for_actor"]
    copies=mapping["copy_index"]
    all(x->x isa Integer && !(x isa Bool), rows) &&
    all(x->x isa Integer && !(x isa Bool), copies) || error("映射索引必须为整数")
    rows==[1; repeat(collect(2:length(pa)); inner = k)] &&
    copies==[1; repeat(collect(1:k), length(pa)-1)] || error("父子编号或顺序错误")
    length(ca)==1+k*(length(pa)-1) && ca[1]==pa[1] || error("主体数或运营商改变")
    mapping["parent_ids"]==[a["id"] for a in pa] && mapping["child_ids"]==[a["id"] for a in ca] || error("主体身份表不符")
    Set(keys(p))==Set(keys(c)) || error("输入顶层字段改变")
    for key in setdiff(collect(keys(p)), ["actors", "devices"])
        p[key]==c[key] || error("拆分改变物理或共同输入：$key")
    end
    for j in 2:length(ca)
        i=rows[j]
        a, b=pa[i], ca[j]
        Set(keys(a))==Set(keys(b)) || error("主体字段改变")
        expected_id=k==1 ? a["id"] : "split_$(i-1)_$(copies[j])_of_$(k)"
        b["id"]==expected_id || error("非确定性子主体ID")
        for key in ("P_load", "H_load", "P_preferred", "H_preferred")
            k .* b[key]==a[key] || error("负荷/偏好未精确等分或发生下溢")
        end
        for key in ("sat_P", "sat_H")
            b[key]/k==a[key] || error("不满意度系数缩放不符")
        end
        changed=("id", "P_load", "H_load", "P_preferred", "H_preferred", "sat_P", "sat_H")
        for key in setdiff(collect(keys(a)), collect(changed))
            a[key]==b[key] || error("未声明的主体变化：$key")
        end
    end
    length(p["devices"])==length(c["devices"]) || error("拆分不允许复制或丢弃设备")
    for (a, b) in zip(p["devices"], c["devices"])
        Set(keys(a))==Set(keys(b)) || error("设备字段改变")
        b["owner"]==(a["owner"]==1 ? 1 : 2+(a["owner"]-2)*k) || error("整台设备归属不符")
        all(a[key]==b[key] for key in keys(a) if key!="owner") || error("设备物理参数改变")
    end
    k==1 && child.source_text!=parent.source_text && error("一倍对照必须保留原字节")
    Dict{String,Any}(
        "input_rule_pass"=>true,
        "parent_sha256"=>parent.sha256,
        "child_sha256"=>child.sha256,
        "parent_aggregators"=>length(pa)-1,
        "child_aggregators"=>length(ca)-1,
        "device_count"=>length(p["devices"]),
        "scope"=>"central_resource_schedule_projection_equivalence; not_AG0_or_payoff_equivalence",
        "physical_feasibility_certified"=>false,
    )
end

"""
    r9_split_cost_identity(parent, child, mapping, child_values)

R9-SC3：独立重算子调度、聚合调度的资源费用及Jensen不满意度差，单位CNY。
差等于各父主体内子负荷偏差方差乘以冻结系数与时间步；等分时为零，一般非负。
函数不认证输入数值可行，也不把聚合后较低的实际费用冒充子问题的求解器目标或最优界。
"""
function r9_split_cost_identity(parent::R9TradingCase, child::R9TradingCase, mapping, values)
    collapsed=r9_split_values(parent, child, mapping, values; direction = :aggregate)
    parent_cost=r9_trading_costs(parent, collapsed)
    child_cost=r9_trading_costs(child, values)
    k=mapping["multiplier"]
    variance=0.0
    for i in 2:length(parent.data["actors"]), carrier in ("P", "H"), t in 1:parent.data["T"]
        indices=findall(==(i), mapping["parent_for_actor"])
        δ=[
            child.data["actors"][j][carrier*"_preferred"][t]-values[carrier*"_D"][j][t] for
            j in indices
        ]
        meanδ=sum(δ)/k
        variance+=parent.data["dt_h"]*k*parent.data["actors"][i]["sat_"*carrier]*sum(
            (δ .- meanδ) .^ 2,
        )
    end
    all(isfinite, (parent_cost.total, child_cost.total, variance)) || error("拆分成本非有限")
    Dict{String,Any}(
        "parent_cost_CNY"=>parent_cost.total,
        "child_cost_CNY"=>child_cost.total,
        "variance_gap_CNY"=>variance,
        "identity_error_CNY"=>child_cost.total-parent_cost.total-variance,
        "epigraph_sum_difference_CNY"=>parent.data["dt_h"]*sum(
            sum(sum, values[key])-sum(sum, collapsed[key]) for key in ("w_P", "w_H")
        ),
        "scope"=>"saved_values_algebra_only; feasibility_and_optimality_require_separate_checks",
    )
end
