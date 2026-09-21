const R5_MARKET_CORE_FILE = @__FILE__

"""
    R5MarketCase(data)

第5章(5-34)至(5-42)的确定性日前能量/备用联合出清输入。
用电与购电均为正，MW/MWh/h/合成美元；报价是固定输入，不是策略报价决策。
PTDF为线路×节点的给定直流灵敏度，本接口不声称交流潮流或备用激活后线路可交付性。
"""
struct R5MarketCase
    data::Dict{String,Any}
    sha256::String
end

function r5_market_text(d)
    sprint(io->TOML.print(io, d; sorted = true))
end

function R5MarketCase(input::AbstractDict)
    d=deepcopy(Dict{String,Any}(string(k)=>v for (k, v) in input))
    d["schema"]=="r5-market-case-v1" || error("市场输入版本错误")
    d["origin"] in ("synthetic", "public_adapted", "thesis_verified") || error("缺少输入来源")
    !isempty(strip(d["name"])) || error("案例名称不能为空")
    for (key, expected) in (
        ("power", "MW"),
        ("energy", "MWh"),
        ("time", "h"),
        ("energy_price", "USD/MWh"),
        ("reserve_price", "USD/(MW*h)"),
        ("ramp", "MW/h"),
    )
        get(get(d, "units", Dict()), key, nothing)==expected || error("市场单位未显式声明：$key")
    end
    B, T=Int(d["nodes"]), Int(d["T"])
    B>=1 && T>=1 || error("节点和时段必须正数")
    d["nodes"], d["T"]=B, T
    isfinite(d["dt_h"]) && d["dt_h"]>0 || error("时间步必须有限正数")
    length(d["load_MW"])==B && all(length(x)==T for x in d["load_MW"]) ||
        error("固定负荷必须为节点×时段")
    all(isfinite(x)&&x>=0 for row in d["load_MW"] for x in row) || error("固定负荷错误")
    for k in ("reserve_up_MW", "reserve_down_MW")
        length(d[k])==T && all(x->isfinite(x)&&x>=0, d[k]) || error("系统备用需求错误")
    end
    net=d["network"]
    length(net["ptdf"])==length(net["limit_MW"]) || error("PTDF线路数错误")
    all(length(x)==B && all(isfinite, x) for x in net["ptdf"]) || error("PTDF必须线路×节点")
    all(x->isfinite(x)&&x>0, net["limit_MW"]) || error("线路容量必须有限正数")
    # 显式给定参考节点；平衡注入下PTDF参照变换不应改变潮流。
    slack=Int(net["slack_node"])
    1<=slack<=B || error("PTDF参考节点错误")
    all(abs(row[slack])<=1e-12 for row in net["ptdf"]) || error("参考节点PTDF列应为零")
    for kind in ("generators", "ies")
        actors=d[kind]
        isempty(actors) && kind=="generators" && error("至少需要一台发电机")
        length(unique(x["id"] for x in actors))==length(actors) || error("同类主体标识重复")
        for a in actors
            a["id"] isa AbstractString && !isempty(strip(a["id"])) ||
                error("主体标识须为非空字符串")
            a["node"]=Int(a["node"])
            1<=a["node"]<=B || error("主体接入节点错误")
            if kind=="generators"
                for k in (
                    "p_min",
                    "p_max",
                    "p_bid_max",
                    "p_initial",
                    "ramp_up_MW_h",
                    "ramp_down_MW_h",
                    "up_max",
                    "down_max",
                )
                    isfinite(a[k]) && a[k]>=0 || error("发电容量/爬坡输入错误")
                end
                a["p_min"]<=a["p_initial"]<=a["p_max"] || error("初始出力越界")
            else
                for k in ("q_min", "q_max", "purchase_bid_max", "up_max", "down_max")
                    isfinite(a[k]) && a[k]>=0 || error("IES容量/中标界输入错误")
                end
                a["q_min"]<=a["q_max"] || error("购电上下界冲突")
            end
            for k in ("energy_bid", "up_bid", "down_bid")
                x=a[k]
                a[k]=x isa Real ? fill(Float64(x), T) : Float64.(x)
                length(a[k])==T && all(x->isfinite(x)&&x>=0, a[k]) ||
                    error("报价必须非负且维度正确")
            end
        end
    end
    text=r5_market_text(d)
    R5MarketCase(d, bytes2hex(sha256(text)))
end

function r5_market_assert_case(c::R5MarketCase)
    bytes2hex(sha256(r5_market_text(c.data)))==c.sha256 || error("市场输入在构造后被修改")
    nothing
end

"""
    load_r5_market_case(path)

读取显式TOML市场输入并核验节点、时间、有限容量、报价及PTDF形状。
哈希绑定规范化内容；不生成情景，不把缺少字段补为零，不求解。
"""
load_r5_market_case(path::AbstractString) = R5MarketCase(TOML.parsefile(path))

function r5_market_sizes(c)
    d=c.data
    (
        G = length(d["generators"]),
        I = length(d["ies"]),
        B = d["nodes"],
        L = length(d["network"]["limit_MW"]),
        T = d["T"],
    )
end

function r5_market_array(x)
    x isa AbstractMatrix ? Matrix{Float64}(x) : reduce(vcat, permutedims.(x))
end

function r5_market_rows(x)
    [collect(row) for row in eachrow(x)]
end
