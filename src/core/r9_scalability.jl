function r9_split_input_identity(c)
    bytes2hex(sha256(c.source_text))==c.sha256 && TOML.parse(c.source_text)==c.data ||
        error("主体拆分输入的原文本、数据或哈希不一致")
    r9_trading_check(c.data)
end

function r9_split_multiplier(k)
    k isa Integer && !(k isa Bool) && k in (1, 2, 4) ||
        error("本协议仅支持1、2、4倍主体数；不隐式扩展实验域")
    Int(k)
end

"""
    r9_split_aggregators(parent, multiplier)

R9-SC1：将每个聚合商等分为1、2或4个同节点主体，返回`(; case, mapping)`，不求解或写文件。
负荷和偏好（MW）除以倍数，不满意度系数（CNY/(h·MW²)）乘以倍数。
原设备整台归第一子主体；不复制电池、设备状态或二元选择。运营商、网络、背景负荷不变。
倍数1保留原始输入字节。映射另存父子哈希；不原位修改输入。
这是集中资源调度的可比构造，不保证独立自调度、结算收益或ADMM迭代相同。
"""
function r9_split_aggregators(parent::R9TradingCase, multiplier)
    r9_split_input_identity(parent)
    k=r9_split_multiplier(multiplier)
    d=deepcopy(parent.data)
    old=d["actors"]
    actors=[deepcopy(old[1])]
    parent_for_actor=[1]
    copy_index=[1]
    for i in 2:length(old), j in 1:k
        a=deepcopy(old[i])
        if k>1
            a["id"]="split_$(i-1)_$(j)_of_$(k)"
            for key in ("P_load", "H_load", "P_preferred", "H_preferred")
                a[key]=a[key] ./ k
            end
            for key in ("sat_P", "sat_H")
                a[key]*=k
            end
        end
        push!(actors, a)
        push!(parent_for_actor, i)
        push!(copy_index, j)
    end
    d["actors"]=actors
    for g in d["devices"]
        i=g["owner"]
        g["owner"]=i==1 ? 1 : 2+(i-2)*k
    end
    child=k==1 ? R9TradingCase(d, parent.sha256, parent.source_text) : R9TradingCase(d)
    mapping=Dict{String,Any}(
        "schema"=>"r9-aggregator-split-v1",
        "rule"=>"equal_demand_scaled_discomfort_indivisible_devices_to_first_child",
        "multiplier"=>k,
        "parent_sha256"=>parent.sha256,
        "child_sha256"=>child.sha256,
        "parent_for_actor"=>parent_for_actor,
        "copy_index"=>copy_index,
        "parent_ids"=>[a["id"] for a in old],
        "child_ids"=>[a["id"] for a in actors],
    )
    # 反向核对仅允许的字段变化；极小数除法下溢也必须拒绝。
    audit_r9_aggregator_split(parent, child, mapping)
    (; case = child, mapping)
end

"""
    r9_split_values(parent, child, mapping, values; direction=:lift)

R9-SC2：只变换完整集中调度的数值字典，不复制求解状态、界或验收结论。
`:lift`等分`P_D/H_D/w_P/w_H`；`:aggregate`按父主体求和。
设备、电网、逐热节点流量及开关数值保持原样。返回新字典后须按目标输入重新独立验算。
不接受局部零售或运营商消息副本；该变换不能注入正式分布运行的初始化。
"""
function r9_split_values(
    parent::R9TradingCase,
    child::R9TradingCase,
    mapping,
    values;
    direction = :lift,
)
    audit_r9_aggregator_split(parent, child, mapping)
    direction in (:lift, :aggregate) || error("未知主体数值变换方向")
    any(haskey(values, key) for key in ("boundary", "P_buy", "P_sell", "H_buy", "H_sell")) &&
        error("只允许完整集中调度；不变换零售计划或运营商消息副本")
    all(haskey(values, key) for key in ("P_grid", "Q_grid", "m_source", "m_load")) ||
        error("缺少完整网络数值")
    source=direction==:lift ? parent : child
    dest=direction==:lift ? child : parent
    T=parent.data["T"]
    k=mapping["multiplier"]
    rows=mapping["parent_for_actor"]
    out=deepcopy(values)
    for key in ("P_D", "H_D", "w_P", "w_H")
        haskey(values, key) &&
        length(values[key])==length(source.data["actors"]) &&
        all(x->length(x)==T && all(y->y isa Real && isfinite(y), x), values[key]) ||
            error("主体数值形状或有限性错误：$key")
        if direction==:lift
            out[key]=[values[key][i] ./ (i==1 ? 1 : k) for i in rows]
        else
            out[key]=[zeros(T) for _ in dest.data["actors"]]
            for (j, i) in enumerate(rows)
                out[key][i].+=values[key][j]
            end
        end
        all(x->all(isfinite, x), out[key]) || error("主体数值变换溢出")
    end
    out
end
