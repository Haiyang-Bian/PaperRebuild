"""
    r9_boundary_contract(case)

R9-DC1：由原设备和负荷边界推导主体通信量的有限盒，不求解、不修改输入。
按主体2…A、每主体四行排列净电注入、无功负荷、热源输出、热需求，单位MW/Mvar/MW/MW；
列为时段。热需求包含储热充热，热源包含储热放热，不能仅传净热量。
盒包含原主体可行域的全部边界；它不是设备联合可行域的充分描述。
每行尺度为全时域最大绝对边界，恒零行取1，归一化不改变物理边界或A1。
"""
function r9_boundary_contract(c::R9TradingCase)
    TOML.parse(c.source_text)==c.data || error("分布输入被原位改变")
    d=c.data
    a, g, T=d["actors"], d["devices"], d["T"]
    lower=zeros(4(length(a)-1), T)
    upper=similar(lower)
    for i in 2:length(a), t in 1:T
        owned=filter(x->x["owner"]==i, g)
        cap(kinds) = sum(x["availability_MW"][t] for x in owned if x["kind"] in kinds; init = 0.0)
        pmin=sum(x["power_min_MW"] for x in owned if x["kind"]=="CHP"; init = 0.0)
        hmin=sum(x["heat_ratio"]*x["power_min_MW"] for x in owned if x["kind"]=="CHP"; init = 0.0)
        hmax=sum(
            x["availability_MW"][t]*x["heat_ratio"] for x in owned if x["kind"] in ("CHP", "P2H");
            init = 0.0,
        )+cap(("HS",))
        plo, phi=((1-a[i]["flex"])*a[i]["P_load"][t], (1+a[i]["flex"])*a[i]["P_load"][t])
        hlo, hhi=((1-a[i]["flex"])*a[i]["H_load"][t], (1+a[i]["flex"])*a[i]["H_load"][t])
        rows=(4(i-2)+1):(4(i-1))
        lower[rows, t]=[pmin-cap(("P2H", "BS"))-phi, a[i]["Q_ratio"]*plo, hmin, hlo]
        upper[rows, t]=[cap(("CHP", "PV", "BS"))-plo, a[i]["Q_ratio"]*phi, hmax, hhi+cap(("HS",))]
    end
    all(isfinite, lower) && all(isfinite, upper) && all(lower .<= upper) ||
        error("通信边界非有限或矛盾")
    scale=[max(maximum(abs, lower[k, :]), maximum(abs, upper[k, :])) for k in axes(lower, 1)]
    scale[scale .== 0].=1.0
    (;
        lower,
        upper,
        scale,
        actors = collect(2:length(a)),
        channels = ["P_net", "Q_load", "H_source", "H_demand"],
        units = ["MW", "Mvar", "MW", "MW"],
        input_sha256 = c.sha256,
    )
end

"""
    r9_trading_boundary(case, values; actor=0)

R9-DC1：仅从保存的设备/负荷数值重算通信量，不读取JuMP表达式。
actor=0返回全部聚合商四行一组的矩阵；actor∈2…A返回指定主体的四行。
运营商副本不在此函数中冒充实际主体控制；检查一致性时须另外比较。
"""
function r9_trading_boundary(c::R9TradingCase, s; actor = 0)
    TOML.parse(c.source_text)==c.data || error("分布输入被原位改变")
    d=c.data
    a, g, T=d["actors"], d["devices"], d["T"]
    actor==0 || actor in 2:length(a) || error("通信主体编号错误")
    selected=actor==0 ? collect(2:length(a)) : [actor]
    message=zeros(4length(selected), T)
    for (j, i) in enumerate(selected), t in 1:T
        owned=findall(x->x["owner"]==i, g)
        message[4j-3, t]=sum(s["P_gen"][k][t]-s["P_cons"][k][t] for k in owned; init = 0.0)-s["P_D"][i][t]
        message[4j-2, t]=a[i]["Q_ratio"]*s["P_D"][i][t]
        message[4j-1, t]=sum(s["H_gen"][k][t] for k in owned; init = 0.0)
        message[4j, t]=s["H_D"][i][t]+sum(s["H_cons"][k][t] for k in owned; init = 0.0)
    end
    all(isfinite, message) || error("通信原值包含非有限数")
    message
end
"""
    R9DistributedSpec(; algorithm=:r9_boundary_admm_fixed_v1, rho=1, max_iterations=1000)

R9-DC4：多主体边界一致性ADMM的冻结规则。fixed版须显式固定全部离散选择；
mip版保留整数，仅作为启发式，不能继承凸收敛保证。两版均从零消息/乘子开始，
使用固定正ρ、A4原始/对偶无穷范数1e-4及独立合并A1，不接收集中解初值。
"""
struct R9DistributedSpec
    algorithm::Symbol
    rho::Float64
    max_iterations::Int
    function R9DistributedSpec(;
        algorithm = :r9_boundary_admm_fixed_v1,
        rho = 1.0,
        max_iterations = 1000,
    )
        algorithm in (:r9_boundary_admm_fixed_v1, :r9_boundary_admm_mip_v1) ||
            error("未知分布算法版本")
        rho isa Real && isfinite(rho) && rho>0 || error("ρ须为有限正数")
        max_iterations isa Integer && 0<max_iterations<=1000 || error("迭代上限须为1…1000")
        new(algorithm, rho, max_iterations)
    end
end

"""R9-DC4：仅从冻结输入得到无量纲费用尺度；它不是可行费用或最优费用界。"""
function r9_distributed_cost_scale(c)
    d=c.data
    raw=d["dt_h"]*sum(abs, d["grid_price"])*d["electric"]["grid_max_MW"]
    for g in d["devices"]
        raw+=d["dt_h"]*abs(g["cost_CNY_MWh"])*sum(g["availability_MW"])
    end
    for a in d["actors"], key in ("P", "H"), t in 1:d["T"]
        lo, hi=(1-a["flex"])*a[key*"_load"][t], (1+a["flex"])*a[key*"_load"][t]
        pref=a[key*"_preferred"][t]
        raw+=d["dt_h"]*a["sat_"*key]*max(abs(lo-pref), abs(hi-pref))^2
    end
    isfinite(raw) || error("费用尺度非有限")
    max(1.0, raw)
end

"""核对全部离散字段，拒绝固定/整数版本混用；不从已有集中解补全缺失模式。"""
function r9_distributed_modes(c, modes, spec)
    if spec.algorithm==:r9_boundary_admm_mip_v1
        modes===nothing || error("整数启发式不接受隐藏的固定模式")
        return nothing
    end
    modes isa AbstractDict || error("连续分布算法需要显式完整模式")
    shapes=Dict(
        "z_storage"=>(length(c.data["devices"]), c.data["T"]),
        "heat_direction"=>(length(c.data["heat"]["pipes"]), c.data["T"]),
    )
    if haskey(c.data, "network_control")
        shapes["u_E"]=(length(c.data["electric"]["edges"]), c.data["T"])
        shapes["u_H"]=(length(c.data["heat"]["pipes"]), 1)
    end
    Set(keys(modes))==Set(keys(shapes)) || error("固定模式字段不完整或多余")
    for (key, shape) in shapes
        size(modes[key])==shape && all(x->x in (0, 1), modes[key]) ||
            error("固定模式形状或取值错误")
    end
    Dict(k=>Int.(v) for (k, v) in modes)
end
