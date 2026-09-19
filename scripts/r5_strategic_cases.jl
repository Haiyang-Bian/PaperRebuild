# 公开合成构造规则；读既有风险物理输入，明确改变的只有外部市场与日前计费归属。
function r5_strategic_fixture(risk_name = "hard_zero")
    root = normpath(joinpath(@__DIR__, ".."))
    path = joinpath(root, "configs", "r5", "risk", risk_name*".toml")
    parent = load_r5_risk_case(path)
    risk = deepcopy(parent.data)
    T = first(risk["commitment"]["scenarios"])["case"]["T"]
    dt = first(risk["commitment"]["scenarios"])["case"]["dt_h"]
    for k in ("energy_price", "up_price", "down_price")
        risk["commitment"]["day_ahead"][k] = zeros(T)
    end
    market = Dict{String,Any}(
        "schema"=>"r5-market-case-v1",
        "name"=>"competitive_"*risk_name,
        "origin"=>"synthetic",
        "description"=>"One exogenous generator, common 100 USD prices, explicit abundant supply.",
        "T"=>T,
        "dt_h"=>dt,
        "nodes"=>1,
        "load_MW"=>[fill(1.0, T)],
        "reserve_up_MW"=>fill(0.1, T),
        "reserve_down_MW"=>fill(0.1, T),
        "units"=>Dict(
            "power"=>"MW",
            "energy"=>"MWh",
            "time"=>"h",
            "energy_price"=>"USD/MWh",
            "reserve_price"=>"USD/(MW*h)",
            "ramp"=>"MW/h",
        ),
        "network"=>Dict("ptdf"=>Vector{Float64}[], "limit_MW"=>Float64[], "slack_node"=>1),
        "generators"=>[
            Dict{String,Any}(
                "id"=>"G",
                "node"=>1,
                "p_min"=>0.0,
                "p_max"=>5.0,
                "p_bid_max"=>5.0,
                "p_initial"=>1.0,
                "ramp_up_MW_h"=>20.0,
                "ramp_down_MW_h"=>20.0,
                "up_max"=>1.0,
                "down_max"=>1.0,
                "energy_bid"=>fill(100.0, T),
                "up_bid"=>fill(100.0, T),
                "down_bid"=>fill(100.0, T),
            ),
        ],
        "ies"=>[
            Dict{String,Any}(
                "id"=>"IES",
                "node"=>1,
                "q_min"=>0.0,
                "q_max"=>1.0,
                "purchase_bid_max"=>1.0,
                "up_max"=>0.08,
                "down_max"=>0.08,
                "energy_bid"=>fill(100.0, T),
                "up_bid"=>fill(100.0, T),
                "down_bid"=>fill(100.0, T),
            ),
        ],
    )
    d = Dict{String,Any}(
        "schema"=>"r5-strategic-case-v1",
        "name"=>"competitive_"*risk_name,
        "origin"=>"synthetic",
        "selection"=>"optimistic_primal_dual",
        "quantity_rule"=>"fixed_offer_capacities",
        "leader_id"=>"IES",
        "market"=>market,
        "risk"=>risk,
        "provenance"=>Dict(
            "parent_risk"=>"configs/r5/risk/"*risk_name*".toml",
            "parent_risk_sha256"=>parent.sha256,
            "changes"=>"External one-node market and explicit zero embedded day-ahead prices; no physical trajectory or risk parameter changes.",
        ),
        "bid_bounds"=>Dict(
            k=>Dict("lower"=>zeros(T), "upper"=>fill(200.0, T)) for
            k in ("energy_bid", "up_bid", "down_bid")
        ),
    )
    R5StrategicCase(d)
end

# 先按手算冻结的阶梯供给例：低价容量0.2，普通负荷0.1，IES原物理总电需求0.142。
# 低价/高价外部发电20/100，IES自发电130。报价20可将购电压在0.1的边界。
function r5_strategic_merit_fixture(; fixed_bid = false)
    d = deepcopy(r5_strategic_fixture().data)
    d["name"] = fixed_bid ? "merit_fixed_bid" : "merit_strategic"
    m = d["market"]
    m["name"] = d["name"]
    m["description"] = "Synthetic analytic step supply; no reserve; frozen before strategy optimization."
    m["load_MW"] = [[0.1]]
    m["reserve_up_MW"] = [0.0]
    m["reserve_down_MW"] = [0.0]
    cheap = deepcopy(m["generators"][1])
    cheap["id"] = "cheap"
    cheap["p_max"] = cheap["p_bid_max"] = 0.2
    cheap["p_initial"] = 0.1
    cheap["energy_bid"] = [20.0]
    m["generators"][1]["id"] = "expensive"
    pushfirst!(m["generators"], cheap)
    for a in vcat(m["generators"], m["ies"])
        a["up_max"] = a["down_max"] = 0.0
    end
    for k in ("R_up_MW", "R_down_MW")
        d["risk"]["commitment"]["bounds"][k] = Dict("lower"=>[0.0], "upper"=>[0.0])
    end
    for k in ("up_bid", "down_bid")
        d["bid_bounds"][k] = Dict("lower"=>[0.0], "upper"=>[0.0])
    end
    if fixed_bid
        d["bid_bounds"]["energy_bid"] = Dict("lower"=>[100.0], "upper"=>[100.0])
    end
    d["provenance"]["changes"] *= " Analytic step supply with ordinary load 0.1 and low-price capacity 0.2; all reserve awards explicitly zero; parent IES device/history unchanged."
    R5StrategicCase(d)
end

# 价格选择负例：全部上备用报价容量恰好满足系统需求，价格缺少稀缺上限规则。
function r5_strategic_scarcity_fixture()
    d=deepcopy(r5_strategic_fixture().data)
    d["name"]="scarcity_unbounded_price"
    d["market"]["name"]=d["name"]
    d["market"]["reserve_up_MW"]=[0.08]
    d["market"]["generators"][1]["up_max"]=0.0
    d["provenance"]["changes"] *= " Scarcity negative control: IES is sole upward reserve provider, system requirement equals its 0.08 MW offer capacity; no price cap imposed."
    R5StrategicCase(d)
end
