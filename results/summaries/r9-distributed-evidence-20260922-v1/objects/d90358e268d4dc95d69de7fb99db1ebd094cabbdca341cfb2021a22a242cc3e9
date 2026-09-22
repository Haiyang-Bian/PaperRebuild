const R5_EXECUTION_CORE_FILE = @__FILE__

"""
    R5MarketExecutionSpec(; quantity_scale_MW=1.0, price_scale_USD_MWh=100.0)

项目最小范数市场执行规则r5_execution_min_norm_v1；不改变原市场福利目标。
在原始最优面最小化全部成交平方和，再在对偶最优面最小化全部显式乘子平方和。
两个参考尺度必须有限正数；乘子尺度为dt_h×price_scale_USD_MWh。
这是明确的教学执行制度，不是作者规定、悲观双层解或隐式价格上限。
"""
struct R5MarketExecutionSpec
    quantity_scale_MW::Float64
    price_scale_USD_MWh::Float64
    function R5MarketExecutionSpec(; quantity_scale_MW = 1.0, price_scale_USD_MWh = 100.0)
        all(x -> isfinite(x) && x > 0, (quantity_scale_MW, price_scale_USD_MWh)) ||
            error("执行选择尺度必须有限正数")
        new(quantity_scale_MW, price_scale_USD_MWh)
    end
end

r5_execution_spec(s::R5MarketExecutionSpec) = Dict{String,Any}(
    "version" => "r5_execution_min_norm_v1",
    "quantity_scale_MW" => s.quantity_scale_MW,
    "price_scale_USD_MWh" => s.price_scale_USD_MWh,
)
function r5_execution_spec(d::AbstractDict)
    d["version"] == "r5_execution_min_norm_v1" || error("未知执行规则")
    R5MarketExecutionSpec(;
        quantity_scale_MW = d["quantity_scale_MW"],
        price_scale_USD_MWh = d["price_scale_USD_MWh"],
    )
end
r5_execution_hash(x) = bytes2hex(sha256(r5_market_text(x)))

function r5_execution_market_certified(v)
    v["model_pass"] &&
        haskey(v, "relative_gap") &&
        v["relative_gap"] <= 1e-4 &&
        all(x["pass"] for x in v["rows"])
end

function r5_execution_awards(c::R5StrategicCase, mc::R5MarketCase, market)
    bids = Dict(k => only(mc.data["ies"])[k] for k in R5_STRATEGIC_BIDS)
    r5_strategic_market_case(c, bids).sha256 == mc.sha256 || error("执行市场与原策略物理输入不一致")
    for key in R5_STRATEGIC_BIDS, t in eachindex(bids[key])
        lo, hi = c.data["bid_bounds"][key]["lower"][t], c.data["bid_bounds"][key]["upper"][t]
        tol = 1e-6*max(1.0, abs(lo), abs(hi))
        lo-tol <= bids[key][t] <= hi+tol || error("执行报价超出原策略声明范围")
    end
    r5_execution_market_certified(validate_r5_market(mc, market)) ||
        error("固定成交评价需要可信市场原/对偶见证")
    Dict(
        k => Float64.(only(market["values"][v])) for
        (k, v) in (("P_DA_MW", "P_IES"), ("R_up_MW", "R_IES_up"), ("R_down_MW", "R_IES_down"))
    )
end
