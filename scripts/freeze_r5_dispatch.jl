using PaperRebuild, TOML, SHA
include("r5_dispatch_cases.jl")
function freeze_r5_dispatch()
    root=normpath(joinpath(@__DIR__, ".."))
    dest=joinpath(root, "configs", "r5", "dispatch")
    ispath(dest)&&error("不覆盖已冻结IES输入")
    cases=Dict{String,R5DispatchCase}()
    cases["hand"]=R5DispatchCase(r5_dispatch_hand())
    cases["quarter"]=R5DispatchCase(r5_dispatch_hand(; dt = 0.25))
    for (side, pda) in (("up", 0.162), ("down", 0.122))
        d=r5_dispatch_hand()
        d["name"]="hand_$side"
        d["award"]["P_DA_MW"]=[pda]
        d["award"]["R_$(side)_MW"]=[0.02]
        d["realtime"]["alpha_$side"]=[1.0]
        cases[side]=R5DispatchCase(d)
    end
    d=r5_dispatch_hand()
    d["name"]="local_heat"
    d["devices"][1]["p_max_MW"]=0.0
    d["buildings"][1]["P_DH_max_MW"]=0.1
    d["heat"]["sources"][1]["T_min_K"]=320.15
    d["heat"]["sources"][1]["T_max_K"]=320.15
    d["heat"]["pipes"][1]["history_S_K"]=[320.15]
    cases["local_heat"]=R5DispatchCase(d)
    for (name, delta, alpha) in (("unavailable", 0.0, 1.0), ("capacity_denominator", 0.1, 0.1))
        d=r5_dispatch_hand()
        d["name"]=name
        d["award"]["R_up_MW"]=[0.1]
        d["realtime"]["alpha_up"]=[alpha]
        d["realtime"]["delta"]=delta
        cases[name]=R5DispatchCase(d)
    end
    cases["four_period"]=R5DispatchCase(r5_dispatch_teaching())
    parent=joinpath(root, "results", "runs", "r5", "r5-market-depot-20260919", "two_bus--highs")
    market=read_r5_market_run(parent)
    award=r5_award_from_market(parent, only(market.case.data["ies"])["id"])
    for (name, alpha) in
        (("market_no_call", 0.0), ("market_up_10percent", 0.1), ("market_up_full", 1.0))
        d=r5_dispatch_hand()
        d["name"]=name
        d["T"]=4
        d["ambient_K"]=fill(283.15, 4)
        d["electric"]["P_load_MW"]=[zeros(4), fill(30.0, 4)]
        d["electric"]["Q_load_Mvar"]=[zeros(4), fill(0.02, 4)]
        d["electric"]["S_base_MVA"]=100.0
        d["electric"]["pcc_max_MW"]=100.0
        d["electric"]["lines"][1]["P_limit_MW"]=100.0
        d["devices"][2]["p_max_MW"]=2.0
        d["devices"][2]["P_initial_MW"]=0.042
        d["devices"][2]["ramp_up_MW_h"]=2.0
        d["devices"][2]["ramp_down_MW_h"]=2.0
        d["award"]=deepcopy(award)
        d["realtime"]=Dict(
            "alpha_up"=>fill(alpha, 4),
            "alpha_down"=>zeros(4),
            "price"=>fill(100.0, 4),
            "penalty_USD_MWh"=>1000.0,
            "delta"=>0.0,
        )
        d["description"]="Synthetic 30 MW local demand and 2 MW GT; copy certified market awards without scaling. Analytical minimum PCC import 28.042 MW."
        cases[name]=R5DispatchCase(d)
    end
    records=[
        Dict("id"=>"$name--$solver", "case"=>name, "solver"=>solver) for
        name in sort!(collect(keys(cases))) for solver in ("highs", "clarabel")
    ]
    append!(
        records,
        [
            Dict("id"=>"$name--gurobi", "case"=>name, "solver"=>"gurobi") for
            name in ("hand", "four_period")
        ],
    )
    rules=Dict(
        "schema"=>"r5-dispatch-rules-v1",
        "origin"=>"synthetic",
        "version"=>"r5_dispatch_checked_v1",
        "budget_sec"=>60.0,
        "records"=>records,
        "input_sha256"=>Dict(name=>c.sha256 for (name, c) in cases),
        "scope"=>"Given awards, one fully known trajectory. No bidding, risk or AC/hydraulic certification.",
        "market_parent"=>Dict(
            "relative_directory"=>replace(relpath(parent, root), '\\'=>'/'),
            "run_id"=>market.result["run_id"],
            "case_sha256"=>market.case.sha256,
            "result_sha256"=>bytes2hex(sha256(read(joinpath(parent, "result.toml")))),
        ),
        "figure_records"=>[
            "four_period--highs",
            "capacity_denominator--highs",
            "market_no_call--highs",
            "market_up_10percent--highs",
            "market_up_full--highs",
        ],
        "settings"=>Dict(
            "threads"=>1,
            "highs_tolerance"=>1e-9,
            "clarabel_tolerance"=>1e-10,
            "gurobi_tolerance"=>1e-9,
            "seed"=>23,
        ),
    )
    mkpath(dest)
    for (name, c) in cases
        write(joinpath(dest, name*".toml"), PaperRebuild.r5_market_text(c.data))
    end
    write(joinpath(dest, "study.toml"), PaperRebuild.r5_market_text(rules))
    println(
        "Frozen ",
        length(cases),
        " IES inputs and ",
        length(records),
        " runs; no optimization performed.",
    )
end
freeze_r5_dispatch()
