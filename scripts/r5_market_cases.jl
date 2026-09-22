# 合成案例先于正式求解生成；不读取历史候选，也不根据收益更换输入。
function r5_market_study_cases(base)
    cases=Dict("two_bus"=>base)
    hand=deepcopy(base.data)
    merge!(
        hand,
        Dict(
            "name"=>"hand_hour",
            "nodes"=>1,
            "T"=>1,
            "dt_h"=>1.0,
            "description"=>"Synthetic one-hour joint-clearing analytic case; no thesis input.",
            "load_MW"=>[[50.0]],
            "reserve_up_MW"=>[20.0],
            "reserve_down_MW"=>[10.0],
            "network"=>Dict("slack_node"=>1, "ptdf"=>Any[], "limit_MW"=>Float64[]),
        ),
    )
    g=deepcopy(hand["generators"][1])
    merge!(
        g,
        Dict(
            "node"=>1,
            "p_max"=>200.0,
            "p_bid_max"=>200.0,
            "p_initial"=>80.0,
            "ramp_up_MW_h"=>200.0,
            "ramp_down_MW_h"=>200.0,
            "up_max"=>100.0,
            "down_max"=>100.0,
            "energy_bid"=>20.0,
            "up_bid"=>5.0,
            "down_bid"=>2.0,
        ),
    )
    a=deepcopy(hand["ies"][1])
    merge!(
        a,
        Dict(
            "node"=>1,
            "q_max"=>100.0,
            "energy_bid"=>100.0,
            "up_bid"=>2.0,
            "down_bid"=>3.0,
            "up_max"=>0.0,
            "down_max"=>0.0,
        ),
    )
    hand["generators"]=[g]
    hand["ies"]=[a]
    cases["hand_hour"]=R5MarketCase(hand)
    quarter=deepcopy(hand)
    quarter["name"]="hand_quarter"
    quarter["dt_h"]=0.25
    quarter["description"]="Same synthetic powers and per-hour prices; duration 0.25 h."
    cases["hand_quarter"]=R5MarketCase(quarter)
    wide=deepcopy(base.data)
    wide["name"]="wide_line"
    wide["network"]["limit_MW"]=[200.0]
    wide["description"]="Base market with line capacity changed from 70 MW to 200 MW before optimization."
    cases["wide_line"]=R5MarketCase(wide)
    noies=deepcopy(base.data)
    noies["name"]="no_ies"
    noies["ies"]=Any[]
    noies["description"]="Synthetic degeneration: remove IES bids, keep ordinary load and reserve."
    cases["no_ies"]=R5MarketCase(noies)
    over=deepcopy(base.data)
    over["name"]="capacity_infeasible"
    over["load_MW"][2].+=1000.0
    over["description"]="Synthetic infeasibility: add 1000 MW ordinary load at bus 2 in each period."
    cases["capacity_infeasible"]=R5MarketCase(over)
    ramp=deepcopy(hand)
    merge!(
        ramp,
        Dict(
            "name"=>"ramp_memory",
            "T"=>2,
            "load_MW"=>[[20.0, 100.0]],
            "reserve_up_MW"=>zeros(2),
            "reserve_down_MW"=>zeros(2),
            "ies"=>Any[],
            "description"=>"Synthetic two-hour ramp example; next-period scarcity can make the first-hour LMP negative.",
        ),
    )
    cheap=deepcopy(g)
    merge!(cheap, Dict("p_initial"=>20.0, "ramp_up_MW_h"=>20.0, "ramp_down_MW_h"=>20.0))
    expensive=deepcopy(g)
    merge!(expensive, Dict("id"=>"G2", "energy_bid"=>50.0, "p_initial"=>0.0))
    ramp["generators"]=[cheap, expensive]
    cases["ramp_memory"]=R5MarketCase(ramp)
    capped=deepcopy(ramp)
    merge!(
        capped,
        Dict(
            "name"=>"bid_cap",
            "T"=>1,
            "load_MW"=>[[100.0]],
            "reserve_up_MW"=>[0.0],
            "reserve_down_MW"=>[0.0],
            "description"=>"Synthetic generator energy bid cap 40 MW below the 200 MW physical capacity.",
        ),
    )
    capped["generators"][1]["p_initial"]=30.0
    capped["generators"][1]["p_bid_max"]=40.0
    cases["bid_cap"]=R5MarketCase(capped)
    cases
end
