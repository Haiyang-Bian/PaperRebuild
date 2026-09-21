const R5_DISPATCH_CORE_FILE = @__FILE__

# v1保留原字段和哈希；v2价格字段与币种分开，禁止隐式汇率或混用USD字段。
r5_dispatch_currency(d::AbstractDict) = d["schema"]=="r5-dispatch-case-v1" ? "USD" : d["currency"]
r5_dispatch_cost_key(d) = d["schema"]=="r5-dispatch-case-v1" ? "cost_USD_MWh" : "cost_per_MWh"
r5_dispatch_penalty_key(d) =
    d["schema"]=="r5-dispatch-case-v1" ? "penalty_USD_MWh" : "penalty_per_MWh"
r5_dispatch_device_cost(d, device) = device[r5_dispatch_cost_key(d)]
r5_dispatch_penalty(d) = d["realtime"][r5_dispatch_penalty_key(d)]

"""
    r5_building_coefficients(C, G, dt)

将单区建筑隐式Euler能量平衡写为论文(2-72)/(5-27)的离散系数。
热容C为MWh/K、传热系数G为MW/K、步长dt为h，返回η_H=dt/C (K/MW)、U=dt*G/C。
这是项目的量纲恢复，不声称作者给出了同一组连续参数。旧building_step接口不变。
"""
function r5_building_coefficients(C, G, dt)
    all(isfinite, (C, G, dt)) && C>0 && G>=0 && dt>0 ||
        throw(ArgumentError("建筑热容、传热系数或步长错误"))
    (; η_H = dt/C, U = dt*G/C)
end

"""
    r5_building_temperature(previous, H_D, H_DH, ambient, C, G, dt)

用建筑接收的总热功率H_D+H_DH (MW)计算下一时段温度K。
依据PDF43的(2-72)和PDF88的总热量定义，采用版修正(5-27)遗漏帽号的解释。
室温/边界采用K，热容MWh/K、传热MW/K、步长h；只求值，不求解或裁剪舒适边界。
"""
function r5_building_temperature(previous, H_D, H_DH, ambient, C, G, dt)
    k=r5_building_coefficients(C, G, dt)
    all(isfinite, (previous, H_D, H_DH, ambient)) &&
    min(previous, ambient)>0 &&
    min(H_D, H_DH)>=0 || throw(ArgumentError("楼宇温度或受热错误"))
    (previous+k.η_H*(H_D+H_DH)+k.U*ambient)/(1+k.U)
end

"""
    R5DispatchCase(data)

第5章给定日前成交及调用轨迹的确定性IES补救输入；v1为原USD，v2显式currency及中性价格字段。
v2支持USD/CNY，单位声明必须相符；不转换货币，旧输入不自动迁移。
支持线性电压幅值潮流、固定正向流量供回水历史、CHP/GT/PV/EB及建筑本地加热。
不包含交流损耗、水压、储能、策略报价或风险约束；C/G、初始历史和终端规则均须显式提供。
"""
struct R5DispatchCase
    data::Dict{String,Any}
    sha256::String
end

function r5_dispatch_vector(x, T, label; lower = -Inf, upper = Inf)
    a=x isa Real ? fill(Float64(x), T) : Float64.(x)
    length(a)==T && all(v->isfinite(v)&&lower<=v<=upper, a) || error("轨迹错误：$label")
    a
end

function R5DispatchCase(input::AbstractDict)
    d=deepcopy(Dict{String,Any}(string(k)=>v for (k, v) in input))
    d["schema"] in ("r5-dispatch-case-v1", "r5-dispatch-case-v2") || error("IES输入版本错误")
    currency=r5_dispatch_currency(d)
    currency in ("USD", "CNY") || error("未支持的显式币种")
    get(d, "currency", currency)==currency || error("v1价格字段只能采用USD")
    if d["schema"]=="r5-dispatch-case-v2"
        all(!haskey(a, "cost_USD_MWh") for a in d["devices"]) &&
        !haskey(d["realtime"], "penalty_USD_MWh") || error("v2不接受混合币种旧字段")
    end
    d["origin"] in ("synthetic", "public_adapted", "thesis_verified") || error("缺少输入来源")
    !isempty(strip(d["name"])) || error("案例名为空")
    for (k, unit) in (
        ("power", "MW"),
        ("reactive", "Mvar"),
        ("energy", "MWh"),
        ("time", "h"),
        ("temperature", "K"),
        ("flow", "kg/s"),
        ("heat_capacity", "MWh/K"),
        ("heat_transfer", "MW/K"),
        ("energy_price", currency*"/MWh"),
        ("reserve_price", currency*"/(MW*h)"),
    )
        get(get(d, "units", Dict()), k, nothing)==unit || error("IES单位未声明：$k")
    end
    T=Int(d["T"])
    T>=1 && isfinite(d["dt_h"]) && d["dt_h"]>0 || error("时域错误")
    d["T"]=T
    d["ambient_K"]=r5_dispatch_vector(d["ambient_K"], T, "环境"; lower = 1)
    e=d["electric"]
    B=Int(e["nodes"])
    root=Int(e["root"])
    B>=1 && 1<=root<=B || error("电网节点错误")
    e["nodes"], e["root"]=B, root
    for k in ("P_load_MW", "Q_load_Mvar")
        length(e[k])==B || error("节点负荷维度错误")
        e[k]=[r5_dispatch_vector(x, T, k; lower = 0) for x in e[k]]
    end
    all(
        isfinite(e[k]) for k in (
            "S_base_MVA",
            "v_ref_pu",
            "v_min_pu",
            "v_max_pu",
            "pcc_min_MW",
            "pcc_max_MW",
            "qcc_min_Mvar",
            "qcc_max_Mvar",
        )
    ) || error("电网边界非有限")
    e["S_base_MVA"]>0 &&
    0<e["v_min_pu"]<=e["v_ref_pu"]<=e["v_max_pu"] &&
    0<=e["pcc_min_MW"]<=e["pcc_max_MW"] &&
    e["qcc_min_Mvar"]<=e["qcc_max_Mvar"] || error("电网边界冲突")
    lines=e["lines"]
    length(lines)==B-1 || error("仅支持固定径向电网")
    parent=zeros(Int, B)
    for l in lines
        i, j=Int(l["from"]), Int(l["to"])
        1<=i<=B && 1<=j<=B && i!=j && j!=root && parent[j]==0 || error("支路/父节点错误")
        parent[j]=i
        l["from"], l["to"]=i, j
        for k in ("r_pu", "x_pu", "P_limit_MW", "Q_limit_Mvar")
            isfinite(l[k]) && l[k]>=0 || error("电支路参数错误")
        end
    end
    for b in 1:B
        n=b
        seen=Set{Int}()
        while n!=root
            n!=0 && !(n in seen) || error("电网环路或断开")
            push!(seen, n)
            n=parent[n]
        end
    end
    h=d["heat"]
    get(h, "terminal_rule", nothing)=="free" || error("本批管温终端须显式为free；尚未实现恢复尾段")
    N=Int(h["nodes"])
    h["nodes"]=N
    N>=1 && isfinite(h["c_J_kgK"]) && h["c_J_kgK"]>0 || error("热网节点/比热错误")
    for k in ("S_min_K", "S_max_K", "R_min_K", "R_max_K")
        isfinite(h[k]) && h[k]>0 || error("热网温度界错误")
    end
    h["S_min_K"]<=h["S_max_K"] && h["R_min_K"]<=h["R_max_K"] || error("热网温度界冲突")
    sources, buildings=h["sources"], d["buildings"]
    for entries in (sources, buildings, d["devices"], lines, h["pipes"])
        ids=[x["id"] for x in entries]
        length(unique(ids))==length(ids) && all(x->x isa String&&!isempty(strip(x)), ids) ||
            error("标识为空或重复")
    end
    for s in sources
        1<=s["node"]<=N && isinteger(s["node"]) && isfinite(s["m_kg_s"]) && s["m_kg_s"]>0 ||
            error("热源端口错误")
        s["node"]=Int(s["node"])
        all(isfinite(s[k]) for k in ("T_min_K", "T_max_K")) && 0<s["T_min_K"]<=s["T_max_K"] ||
            error("热源温度界错误")
    end
    for b in buildings
        1<=b["heat_node"]<=N &&
        1<=b["electric_node"]<=B &&
        isinteger(b["heat_node"]) &&
        isinteger(b["electric_node"]) || error("建筑接入错误")
        b["heat_node"], b["electric_node"]=Int(b["heat_node"]), Int(b["electric_node"])
        all(
            isfinite(b[k]) for k in (
                "m_kg_s",
                "C_MWh_K",
                "G_MW_K",
                "T_initial_K",
                "T_min_K",
                "T_max_K",
                "R_min_K",
                "R_max_K",
                "P_DH_max_MW",
                "COP_DH",
            )
        ) || error("建筑输入非有限")
        b["m_kg_s"]>0 &&
        b["P_DH_max_MW"]>=0 &&
        b["COP_DH"]>0 &&
        0<b["T_min_K"]<=b["T_initial_K"]<=b["T_max_K"] &&
        0<b["R_min_K"]<=b["R_max_K"] || error("建筑边界冲突")
        r5_building_coefficients(b["C_MWh_K"], b["G_MW_K"], d["dt_h"])
        b["terminal_rule"] in ("free", "initial") || error("建筑终端规则必须显式声明")
    end
    for p in h["pipes"]
        1<=p["from"]<=N &&
        1<=p["to"]<=N &&
        p["from"]!=p["to"] &&
        isinteger(p["from"]) &&
        isinteger(p["to"]) || error("热管连接错误")
        p["from"], p["to"]=Int(p["from"]), Int(p["to"])
        k=fixed_flow_kernel(
            p["m_kg_s"],
            p["rho_kg_m3"],
            p["area_m2"],
            p["length_m"],
            d["dt_h"],
            p["loss_W_mK"];
            c_w = h["c_J_kgK"]/1000,
        )
        for name in ("history_S_K", "history_R_K")
            length(p[name])>=maximum(k.lags) && all(x->isfinite(x)&&x>0, p[name]) ||
                error("热管历史不足或不合法")
        end
    end
    for n in 1:N
        mi=sum(p["m_kg_s"] for p in h["pipes"] if p["to"]==n; init = 0.0)
        mo=sum(p["m_kg_s"] for p in h["pipes"] if p["from"]==n; init = 0.0)
        ms=sum(s["m_kg_s"] for s in sources if s["node"]==n; init = 0.0)
        ml=sum(b["m_kg_s"] for b in buildings if b["heat_node"]==n; init = 0.0)
        mi+ms>0 && mo+ml>0 && abs(mi+ms-mo-ml)<=1e-10*max(1.0, mi+ms, mo+ml) ||
            error("固定热流不守恒或有未定义混合节点")
    end
    sourceids=Set(s["id"] for s in sources)
    for a in d["devices"]
        a["kind"] in ("CHP", "GT", "PV", "EB") || error("未支持的设备")
        1<=a["node"]<=B && isinteger(a["node"]) || error("设备电节点错误")
        a["node"]=Int(a["node"])
        for k in ("p_min_MW", "p_max_MW", "q_min_Mvar", "q_max_Mvar", r5_dispatch_cost_key(d))
            isfinite(a[k]) || error("设备边界非有限")
        end
        0<=a["p_min_MW"]<=a["p_max_MW"] &&
        a["q_min_Mvar"]<=a["q_max_Mvar"] &&
        r5_dispatch_device_cost(d, a)>=0 || error("设备边界错误")
        if a["kind"] in ("CHP", "EB")
            a["source_id"] in sourceids && isfinite(a["heat_ratio"]) && a["heat_ratio"]>0 ||
                error("热设备端口/转换系数错误")
        end
        if a["kind"] in ("CHP", "GT")
            a["p_min_MW"]<=a["P_initial_MW"]<=a["p_max_MW"] || error("设备初值错误")
            for k in ("ramp_up_MW_h", "ramp_down_MW_h")
                isfinite(a[k]) && a[k]>=0 || error("设备爬坡错误")
            end
        elseif a["kind"]=="PV"
            a["available_MW"]=r5_dispatch_vector(
                a["available_MW"],
                T,
                "PV";
                lower = a["p_min_MW"],
                upper = a["p_max_MW"],
            )
        end
    end
    award=d["award"]
    award["origin"] in ("synthetic", "verified_market") || error("成交来源错误")
    for k in ("P_DA_MW", "R_up_MW", "R_down_MW")
        award[k]=r5_dispatch_vector(award[k], T, k; lower = 0)
    end
    for k in ("energy_price", "up_price", "down_price")
        award[k]=r5_dispatch_vector(award[k], T, k)
    end
    if award["origin"]=="verified_market"
        currency=="USD" || error("现有出清父记录为USD；不自动换算为其他币种")
        all(
            haskey(award, k) && !isempty(award[k]) for
            k in ("parent_run_id", "parent_case_sha256", "parent_result_sha256", "ies_id")
        ) || error("市场成交来源链缺失")
        award["dt_h"]==d["dt_h"] || error("市场与IES时间步不同")
    end
    rt=d["realtime"]
    for k in ("alpha_up", "alpha_down")
        rt[k]=r5_dispatch_vector(rt[k], T, k; lower = 0, upper = 1)
    end
    rt["price"]=r5_dispatch_vector(rt["price"], T, "实时价格")
    isfinite(r5_dispatch_penalty(d)) &&
    r5_dispatch_penalty(d)>0 &&
    isfinite(rt["delta"]) &&
    0<=rt["delta"]<=1 || error("交付考核参数错误")
    # 5-4按容量总和归一化，不能擅自换成实际调用量；两侧都按dt积分。
    for t in 1:T
        e["pcc_min_MW"]<=award["P_DA_MW"][t]-award["R_up_MW"][t] &&
        award["P_DA_MW"][t]+award["R_down_MW"][t]<=e["pcc_max_MW"] || error("成交越过PCC容量界")
    end
    R5DispatchCase(d, r5_market_digest(d))
end

"""
    load_r5_dispatch_case(path)

读取确定性IES补救TOML，严格检查热流守恒、管道历史、建筑热容、单位和成交边界。
哈希绑定规范化输入，不用零值填补缺失参数；不可交付调用留给模型报告，不擅自修改。
"""
load_r5_dispatch_case(path::AbstractString) = R5DispatchCase(TOML.parsefile(path))

function r5_dispatch_assert_case(c::R5DispatchCase)
    r5_market_digest(c.data)==c.sha256 || error("IES输入构造后被修改")
end

function r5_dispatch_sizes(c)
    d=c.data
    (;
        T = d["T"],
        B = d["electric"]["nodes"],
        L = length(d["electric"]["lines"]),
        N = d["heat"]["nodes"],
        A = length(d["heat"]["pipes"]),
        S = length(d["heat"]["sources"]),
        J = length(d["buildings"]),
        G = length(d["devices"]),
    )
end

"""
    r5_award_from_market(directory, ies_id)

只读已保存且通过原问题/KKT/独立对偶检查的市场运行，提取指定IES成交和价格。
返回带父运行、输入及原值哈希的字典；不缩放MW、不修改成交、不重新求解。
市场的容量中标仍须由独立IES物理输入核查，提取成功不等于备用可交付。
"""
function r5_award_from_market(directory::AbstractString, ies_id::AbstractString)
    x=read_r5_market_run(directory)
    x.validation["optimality_pass"] &&
    get(get(x.result, "independent_dual", Dict()), "verified", false) ||
        error("市场运行没有完整原对偶认证")
    i=only(findall(a->a["id"]==ies_id, x.case.data["ies"]))
    b=x.case.data["ies"][i]["node"]
    Dict{String,Any}(
        "origin"=>"verified_market",
        "parent_run_id"=>x.result["run_id"],
        "parent_case_sha256"=>x.case.sha256,
        "parent_result_sha256"=>bytes2hex(sha256(read(joinpath(directory, "result.toml")))),
        "ies_id"=>ies_id,
        "dt_h"=>x.case.data["dt_h"],
        "P_DA_MW"=>x.result["values"]["P_IES"][i],
        "R_up_MW"=>x.result["values"]["R_IES_up"][i],
        "R_down_MW"=>x.result["values"]["R_IES_down"][i],
        "energy_price"=>x.validation["LMP_USD_MWh"][b],
        "up_price"=>x.validation["reserve_up_price"],
        "down_price"=>x.validation["reserve_down_price"],
    )
end
