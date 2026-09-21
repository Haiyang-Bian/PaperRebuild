const R5_RISK_CORE_FILE=@__FILE__

"""
    R5RiskCase(data)

第5章有限支持分布鲁棒费用及联合室温风险输入，版本r5-risk-case-v1。
内嵌已核查共同承诺模板；ambiguity给出冻结距离和半径，epsilon限制最坏联合违约概率。
temperature_domain是显式项目室温物理域，必须包含原舒适界；只放松舒适，不放松终端或设备关系。
本模型为固定价格、完整轨迹补救基准，不是策略报价、连续支持或样本外可靠性保证。
"""
struct R5RiskCase
    data::Dict{String,Any}
    sha256::String
end

function r5_risk_transport_input(weights, distance, scores, radius)
    p=Float64.(weights)
    n=length(p)
    D=distance isa AbstractMatrix ? Float64.(distance) : r5_market_array(distance)
    q=Float64.(scores)
    n>0&&size(D)==(n, n)&&length(q)==n||error("运输维度错误")
    all(isfinite, p)&&all(p .>= 0)&&abs(sum(p)-1)<=1e-12||error("运输经验概率错误")
    all(isfinite, D)&&all(D .>= 0)&&all(D[i, i]==0 for i in 1:n)||error(
        "运输距离必须非负且对角为零",
    )
    all(isfinite, q)&&isfinite(radius)&&radius>=0||error("运输费用或半径非有限/非法")
    # 本批显式要求度量；不同情景的零距离允许表示重复支持点（伪度量）。
    maximum(abs.(D-transpose(D)))<=1e-12||error("冻结距离不对称")
    all(D[i, j]<=D[i, k]+D[k, j]+1e-12 for i in 1:n, j in 1:n, k in 1:n)||error(
        "冻结距离违反三角不等式",
    )
    (; weights = p, distance = D, scores = q, radius = Float64(radius), n)
end

function R5RiskCase(input::AbstractDict)
    d=deepcopy(Dict{String,Any}(string(k)=>v for (k, v) in input))
    d["schema"]=="r5-risk-case-v1"||error("风险输入版本错误")
    !isempty(strip(d["name"]))||error("风险案例名称为空")
    base=R5CommitmentCase(d["commitment"])
    d["origin"]==base.data["origin"]||error("风险输入来源不一致")
    d["objective"]=="worst_expected_net_cost"||error("风险目标不支持")
    d["event"]=="any_building_time_comfort_violation"||error("联合事件必须覆盖任一楼宇时段越界")
    isfinite(d["epsilon"])&&0<=d["epsilon"]<=1||error("风险上限不在[0,1]")
    a=d["ambiguity"]
    a["support"]=="fixed_scenarios"&&a["distance_unit"]=="normalized_trajectory" ||
        error("本批只支持显式归一化有限支持")
    !isempty(strip(a["distance_provenance"]))||error("缺少冻结距离构造依据")
    p=[s["probability"] for s in base.data["scenarios"]]
    tr=r5_risk_transport_input(p, a["distance"], zeros(length(p)), a["radius"])
    a["distance"]=[collect(tr.distance[i, :]) for i in 1:tr.n]
    a["radius"]=tr.radius
    bs=first(base.data["scenarios"])["case"]["buildings"]
    domain=d["temperature_domain"]
    Set(keys(domain))==Set(b["id"] for b in bs)||error("室温物理域缺失或多余建筑")
    for b in bs
        v=domain[b["id"]]
        Set(keys(v))==Set(("lower_K", "upper_K"))||error("室温物理域字段错误")
        lo, hi=v["lower_K"], v["upper_K"]
        all(isfinite, (lo, hi))&&0<lo<=b["T_min_K"]<=b["T_max_K"]<=hi||error(
            "物理温度域必须包含舒适界",
        )
    end
    d["commitment"]=base.data
    R5RiskCase(d, bytes2hex(sha256(r5_market_text(d))))
end

"""
    load_r5_risk_case(path)

读取全部情景、共同承诺、冻结运输距离、风险上限和室温物理域；不抽样、不优化、不自动校准半径。
"""
load_r5_risk_case(path::AbstractString) = R5RiskCase(TOML.parsefile(path))
r5_risk_assert_case(c) =
    bytes2hex(sha256(r5_market_text(c.data)))==c.sha256||error("风险输入被修改")

# 仅用较宽物理域构造数值/建模视图，原舒适阈值始终保留在原始输入中。
function r5_risk_physical_case(c)
    d=deepcopy(c.data["commitment"])
    for s in d["scenarios"], b in s["case"]["buildings"]
        v=c.data["temperature_domain"][b["id"]]
        b["T_min_K"], b["T_max_K"]=v["lower_K"], v["upper_K"]
    end
    R5CommitmentCase(d)
end

function r5_risk_pattern(c, pattern)
    n=length(c.data["commitment"]["scenarios"])
    pattern===nothing&&return nothing
    length(pattern)==n&&all(x->x in (0, 1), pattern)||error("舒适分支须与情景顺序一致且为0/1")
    Int.(pattern)
end
