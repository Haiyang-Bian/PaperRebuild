const R5_STRATEGIC_CORE_FILE = @__FILE__
const R5_STRATEGIC_BIDS = ("energy_bid", "up_bid", "down_bid")

"""
    R5StrategicCase(data)

第5章单个IES连续价格报价、市场出清与有限支持风险补救的显式连接输入。
采用r5-strategic-case-v1；MW、h、USD沿用两个子模型，不缩放成交量。
selection必须显式为optimistic_primal_dual：上层选择有利的下层最优成交和价格。
该选择规则是项目补充，不是作者未公开实现的证明；不支持多IES领导者或样本外风险保证。
"""
struct R5StrategicCase
    data::Dict{String,Any}
    sha256::String
end

function R5StrategicCase(input::AbstractDict)
    d = deepcopy(Dict{String,Any}(string(k)=>v for (k, v) in input))
    d["schema"] == "r5-strategic-case-v1" || error("策略输入版本错误")
    !isempty(strip(d["name"])) || error("策略案例名称为空")
    d["origin"] == "synthetic" || error("当前策略接口仅验收显式合成输入")
    d["selection"] == "optimistic_primal_dual" || error("须显式声明乐观成交及价格选择")
    d["quantity_rule"] == "fixed_offer_capacities" || error("本批仅优化连续价格，报价容量固定")
    market = R5MarketCase(d["market"])
    risk = R5RiskCase(d["risk"])
    length(market.data["ies"]) == 1 || error("支付代数是全部IES合计，本批只支持单个领导者")
    only(market.data["ies"])["id"] == d["leader_id"] || error("领导者身份错误")
    d["origin"] == market.data["origin"] == risk.data["origin"] || error("来源声明不一致")
    firstcase = first(risk.data["commitment"]["scenarios"])["case"]
    firstcase["schema"]=="r5-dispatch-case-v1" || error("策略市场仍采用原USD输入；v2先用于外生价格")
    market.data["T"] == firstcase["T"] && market.data["dt_h"] == firstcase["dt_h"] ||
        error("市场和补救时域/单位不同；不能自动缩放成交")
    # 支付由真实市场乘子计算，补救子记录的日前常数必须为零，避免重复计费。
    all(iszero, vcat(values(risk.data["commitment"]["day_ahead"])...)) ||
        error("内嵌补救的日前价格必须显式为零；市场支付单独计入")
    bounds = d["bid_bounds"]
    Set(keys(bounds)) == Set(R5_STRATEGIC_BIDS) || error("连续报价边界字段不符")
    T = market.data["T"]
    for key in R5_STRATEGIC_BIDS
        b = bounds[key]
        Set(keys(b)) == Set(("lower", "upper")) || error("报价边界需lower/upper")
        for side in ("lower", "upper")
            b[side] = r5_dispatch_vector(b[side], T, "$key/$side"; lower = 0)
        end
        all(b["lower"] .<= b["upper"]) || error("报价上下界冲突")
    end
    d["market"], d["risk"] = market.data, risk.data
    R5StrategicCase(d, bytes2hex(sha256(r5_market_text(d))))
end

"""
    load_r5_strategic_case(path)

读取含全部市场、补救情景、风险参数及连续报价界的TOML；检查单位和单领导者边界。
不生成数据，不自动清零价格或调整容量，不求解。
"""
load_r5_strategic_case(path::AbstractString) = R5StrategicCase(TOML.parsefile(path))
r5_strategic_assert_case(c) =
    bytes2hex(sha256(r5_market_text(c.data))) == c.sha256 || error("策略输入被修改")

function r5_strategic_market_case(c, bids)
    d = deepcopy(c.data["market"])
    T = d["T"]
    Set(keys(bids)) == Set(R5_STRATEGIC_BIDS) || error("策略报价字段不符")
    for k in R5_STRATEGIC_BIDS
        length(bids[k]) == T && all(isfinite, bids[k]) || error("报价数值/形状不符")
        d["ies"][1][k] = Float64.(bids[k])
    end
    # 不裁剪求解器原值；报价可行性另按A1验证，输入物理结构已经核验。
    R5MarketCase(d, bytes2hex(sha256(r5_market_text(d))))
end
