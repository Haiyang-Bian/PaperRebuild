"""
    R4Case(data)

第4章独立输入与原始TOML文本/哈希；仅支持两个聚合商的合成稳态基准。
功率MW、能量MWh、流量kg/s、温度K、时长h。构造时检查凸性与有限边界。
"""
struct R4Case
    data::Dict{String,Any}
    sha256::String
    source_text::String
end

"""第4章运行选择：operation为central或independent；electric为socp或exact。"""
struct R4Spec
    operation::Symbol
    electric::Symbol
    function R4Spec(; operation = :central, electric = :socp)
        operation in (:central, :independent) || error("未知运行方式")
        electric in (:socp, :exact) || error("未知电网版本")
        new(operation, electric)
    end
end

function r4_text(data)
    io=IOBuffer()
    TOML.print(io, data; sorted = true)
    return String(take!(io))
end
function R4Case(data::AbstractDict)
    text=r4_text(data)
    d=TOML.parse(text)
    r4_check(d)
    return R4Case(d, bytes2hex(sha256(text)), text)
end

"""
    load_r4_case(path)

读取第4章冻结输入；拒绝负二次不满意度、非有限容量、错误单位、索引和交易边界。
保留文件字节哈希，不能将合成数据标为作者参数。
"""
function load_r4_case(path::AbstractString)
    text=read(path, String)
    d=TOML.parse(text)
    r4_check(d)
    return R4Case(d, bytes2hex(sha256(text)), text)
end

function r4_check(d)
    d["schema"]=="r4-case-v1" && d["origin"]=="synthetic" || error("输入版本/来源不支持")
    d["T"] isa Integer && d["T"]>0 || error("时域须为正整数")
    T=d["T"]
    pos(x) = x isa Real && isfinite(x) && x>0
    nonneg(x) = x isa Real && isfinite(x) && x>=0
    pos(d["dt_h"]) || error("时间步长错误")
    d["units"]==Dict(
        "power"=>"MW",
        "energy"=>"MWh",
        "time"=>"h",
        "mass_flow"=>"kg/s",
        "temperature"=>"K",
        "money"=>"USD_synthetic",
    ) || error("单位错误")
    d["p2p_enabled"] isa Bool || error("交易开关错误")
    length(d["grid_price"])==T && all(nonneg, d["grid_price"]) || error("外部电价错误")
    a=d["actors"]
    length(a)==3 && [x["id"] for x in a]==["DSO", "A", "B"] && [x["node"] for x in a]==[1, 2, 3] || error("主体归属错误")
    count(x->x["BS_power_max"]>0, a)<=1 || error("首批最多一组电池")
    for x in a
        for k in (
            "CHP_max",
            "EB_max",
            "HP_max",
            "PV_max",
            "BS_power_max",
            "BS_energy_max",
            "BS_initial",
            "CHP_cost",
            "PV_cost",
            "BS_cost",
            "sat_P",
            "sat_H",
            "Q_ratio",
        )
            nonneg(x[k]) || error("非凸或非法参数: "*k)
        end
        for k in ("heat_ratio", "COP_HP", "COP_EB", "retail_limit", "port_flow_max")
            pos(x[k]) || error("正参数缺失: "*k)
        end
        for k in ("eta_ch", "eta_dis")
            pos(x[k]) && x[k]<=1 || error("储能效率错误")
        end
        0<=x["flex"]<1 || error("负荷调节范围错误")
        0<=x["BS_initial"]<=x["BS_energy_max"] || error("初始能量越界")
        for k in ("P_load", "H_load", "PV_profile")
            length(x[k])==T && all(nonneg, x[k]) || error("时序输入错误")
        end
        all(x["PV_profile"] .<= 1) || error("光伏可用比例错误")
        pbound=max(
            x["CHP_max"]+x["PV_max"]+x["BS_power_max"],
            maximum(x["P_load"])*(1+x["flex"])+x["HP_max"]+x["EB_max"]+x["BS_power_max"],
        )
        hbound=max(
            x["heat_ratio"]*x["CHP_max"]+x["COP_HP"]*x["HP_max"]+x["COP_EB"]*x["EB_max"],
            maximum(x["H_load"])*(1+x["flex"]),
        )
        x["retail_limit"]>=max(pbound, hbound) || error("零售边界不足，合同分解可能改变物理调度")
    end
    all(iszero, a[1]["P_load"]) && all(iszero, a[1]["H_load"]) || error("DSO本批无非市场用户")
    e=d["electric"]
    all(
        pos(e[k]) for k in ("S_base_MVA", "V_base_kV", "grid_max", "Q_grid_max", "v_min", "v_max")
    ) || error("电网边界错误")
    e["v_min"]<=1<=e["v_max"] || error("根电压越界")
    h=d["heat"]
    pos(h["cp"]) || error("比热错误")
    for p in ("source", "load")
        pos(h[p*"_delta_min"]) && pos(h[p*"_delta_max"]) && h[p*"_delta_min"]<=h[p*"_delta_max"] ||
            error("端口温差边界错误")
    end
    for (rows, keys) in (
        (e["edges"], ("P_max", "Q_max", "ell_max")),
        (h["pipes"], ("flow_max", "H_max", "length_m")),
    )
        length(rows)==2 && [(x["from"], x["to"]) for x in rows]==[(1, 2), (2, 3)] || error("首批拓扑应为1→2→3")
        all(pos(x[k]) for x in rows for k in keys) || error("网络容量错误")
    end
    all(nonneg(x[k]) for x in e["edges"] for k in ("r", "x")) || error("阻抗错误")
    for p in h["pipes"]
        all(pos(p[k]) for k in ("S_ref_K", "R_ref_K", "ambient_K")) &&
        nonneg(p["U_W_mK"]) &&
        p["S_ref_K"]>=p["R_ref_K"]>=p["ambient_K"] || error("参考热状态错误")
    end
    s=d["settlement"]
    all(nonneg, vcat(collect(values(s)))) || error("结算价格错误")
    s["P_buy"]>s["P_sell"] && s["H_buy"]>s["H_sell"] || error("买卖价须有正价差")
    return true
end

# R4-P4：U按单根管道定义；供回水相对环境的温差各计一次；W显式转换为MW。
r4_loss(p) = 1e-6*p["U_W_mK"]*p["length_m"]*(p["S_ref_K"]+p["R_ref_K"]-2*p["ambient_K"])
r4_matrix(x) = reduce(vcat, permutedims.(x))
r4_rows(x::AbstractMatrix) = [collect(x[i, :]) for i in axes(x, 1)]
r4_spec(s) = Dict(
    "operation"=>String(s.operation),
    "electric"=>String(s.electric),
    "version"=>"r4_central_checked_v1",
)
