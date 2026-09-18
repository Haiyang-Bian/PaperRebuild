include("r5_dispatch_cases.jl")

# 先按解析基准构造，再冻结；不读取任何求解器结果或参考解。
function r5_commitment_teaching(; dt = 1.0, four_period = false)
    d=four_period ? r5_dispatch_teaching() : r5_dispatch_hand(; dt)
    if !four_period
        d["devices"][2]["p_max_MW"]=0.2
        d["devices"][2]["P_initial_MW"]=0.05
        d["realtime"]["price"]=[80.0]
    end
    T=d["T"]
    day=Dict(
        "energy_price"=>copy(d["award"]["energy_price"]),
        "up_price"=>fill(four_period ? 5.0 : 100.0, T),
        "down_price"=>fill(four_period ? 2.0 : 100.0, T),
    )
    scenarios=Dict{String,Any}[]
    for (id, p, up, down) in
        (("none", 0.5, 0.0, 0.0), ("up", 0.25, 1.0, 0.0), ("down", 0.25, 0.0, 1.0))
        a=deepcopy(d)
        a["name"]="shared_"*id
        a["realtime"]["alpha_up"]=fill(up, T)
        a["realtime"]["alpha_down"]=fill(down, T)
        push!(scenarios, Dict("id"=>id, "probability"=>p, "case"=>a))
    end
    Dict{String,Any}(
        "schema"=>"r5-commitment-case-v1",
        "origin"=>"synthetic",
        "name"=>four_period ? "shared_four_period" : "shared_hand",
        "objective"=>"expected_net_cost",
        "recourse_information"=>"complete_trajectory",
        "comfort"=>"hard_each_scenario",
        "uncertain_fields"=>["realtime.alpha_up", "realtime.alpha_down"],
        "day_ahead"=>day,
        "bounds"=>Dict(
            k=>Dict("lower"=>zeros(T), "upper"=>fill(k=="P_DA_MW" ? 1.0 : 0.08, T)) for
            k in PaperRebuild.R5_COMMITMENT_KEYS
        ),
        "scenarios"=>scenarios,
    )
end

function r5_commitment_inputs()
    hand=r5_commitment_teaching()
    cases=Dict(
        "hand"=>hand,
        "quarter"=>r5_commitment_teaching(; dt = 0.25),
        "four_period"=>r5_commitment_teaching(; four_period = true),
    )
    for name in (
        "no_reserve",
        "fixed_feasible",
        "overcommitted",
        "capacity_denominator",
        "no_call_only",
        "unequal_weights",
    )
        d=deepcopy(hand)
        d["name"]=name
        if name=="no_reserve"
            for k in ("R_up_MW", "R_down_MW")
                d["bounds"][k]["upper"]=[0.0]
            end
        elseif name in ("fixed_feasible", "overcommitted")
            for (k, x) in (
                ("P_DA_MW", 0.08),
                ("R_up_MW", 0.08),
                ("R_down_MW", name=="fixed_feasible" ? 0.062 : 0.08),
            )
                d["bounds"][k]=Dict("lower"=>[x], "upper"=>[x])
            end
        elseif name=="capacity_denominator"
            for s in d["scenarios"]
                s["case"]["realtime"]["delta"]=0.1
            end
        elseif name=="no_call_only"
            d["scenarios"]=[first(d["scenarios"])]
            d["scenarios"][1]["probability"]=1.0
        else
            for (s, p) in zip(d["scenarios"], (0.2, 0.6, 0.2))
                s["probability"]=p
            end
        end
        cases[name]=d
    end
    future=deepcopy(cases["four_period"])
    future["name"]="four_period_future"
    append!(future["uncertain_fields"], ["ambient_K", "electric.P_load_MW", "devices.available_MW"])
    for (i, s) in enumerate(future["scenarios"])
        i==1&&continue
        s["case"]["ambient_K"].+=i==2 ? -1.0 : 1.0
        s["case"]["electric"]["P_load_MW"][2].*=i==2 ? 1.1 : 0.9
        for a in s["case"]["devices"]
            a["kind"]=="PV"&&(a["available_MW"].*=i==2 ? 0.8 : 0.9)
        end
    end
    cases["four_period_future"]=future
    cases
end
