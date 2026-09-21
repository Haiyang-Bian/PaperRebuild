using JuMP, Clarabel, SHA, TOML
include("fixtures/r9_trading.jl")

# 明确固定整数方案后才使用Clarabel；没有将二元变量连续松弛。
function r9_trading_test_solve(
    c;
    stage = :central,
    actor = 0,
    reverse = false,
    storage = nothing,
    frozen = nothing,
)
    G, T=length(c.data["devices"]), c.data["T"]
    z=zeros(Int, G, T)
    storage!==nothing && (z[G, :]=storage)
    modes=Dict(
        "z_storage"=>z,
        "heat_direction"=>fill(reverse ? 0 : 1, length(c.data["heat"]["pipes"]), T),
    )
    b=build_r9_trading_model(c; stage, actor, frozen, modes, optimizer = Clarabel.Optimizer)
    set_silent(b.model)
    set_time_limit_sec(b.model, 60.0)
    optimize!(b.model)
    r=Dict{String,Any}(
        "input_sha256"=>c.sha256,
        "stage"=>String(stage),
        "actor"=>actor,
        "electric"=>"socp",
        "operation"=>stage==:central ? "central" : "independent",
        "termination"=>string(termination_status(b.model)),
    )
    if has_values(b.model) &&
       primal_status(b.model) in (MOI.FEASIBLE_POINT, MOI.NEARLY_FEASIBLE_POINT)
        r["solver_objective"]=objective_value(b.model)
        r["values"]=Dict(k=>PaperRebuild.r2_extract(v) for (k, v) in b.variables)
    end
    stage==:network && (r["frozen_plans"]=frozen)
    return r, b
end

@testset "R9-T1 scale input, original sites and explicit replacements" begin
    root=normpath(joinpath(@__DIR__, ".."))
    c=r9_trading_case(
        joinpath(root, "docs/reading/ch07"),
        joinpath(root, "configs/r9/trading-protocol.toml"),
    )
    d=c.data
    @test length(d["actors"])==9 && length(d["devices"])==13
    @test d["electric"]["nodes"]==44 && d["heat"]["nodes"]==38
    @test length(d["electric"]["edges"])==43 && length(d["heat"]["pipes"])==37
    @test d["electric"]["root"]==44 && d["heat"]["root"]==1
    @test [a["id"] for a in d["actors"] if a["heat_node"]==26]==["A4", "A8"]
    @test d["provenance"]["table_P_total_MW"]≈15.52
    @test d["provenance"]["table_H_total_MW"]≈5.53
    @test d["provenance"]["background_P_peak_MW"]≈25.583
    @test d["provenance"]["background_H_peak_MW"]≈1.70
    @test maximum(sum(a["H_load"] for a in d["actors"] if a["heat_node"]==26))≈2*0.77*1.5
    @test iszero(sum(d["heat"]["H_background_MW"][26]))
    @test maximum(sum(a["P_load"] for a in d["actors"]))≈15.52*1.5
    @test sum(x["power_max_MW"] for x in d["devices"] if x["kind"]=="PV")≈8.0
    @test sum(x["energy_max_MWh"] for x in d["devices"] if x["kind"]=="BS")≈4.0
    @test all(
        x["origin"]=="synthetic_missing_heat_storage" for x in d["devices"] if x["kind"]=="HS"
    )
    b=build_r9_trading_model(c)
    @test b.model_class=="MISOCP"
    @test !b.full_thermal_physics_certified && b.heat_scope=="steady_energy_mass_envelope"
    @test count(is_binary, all_variables(b.model))==24*(37+4)
    @test haskey(b.constraints, "R9-T5-mass-balance")
    @test length(b.constraints["R9-T5-mass-balance"])==38*24
    @test length(b.constraints["ch04-030:031"])==2*44*24
    for mutate in (
        x->(x["units"]["money"]="USD"),
        x->(x["devices"][1]["owner"]=2),
        x->(x["actors"][2]["sat_H"]=-1.0),
        x->(x["actors"][2]["P_load"][1]=NaN),
        x->(x["heat"]["pipes"][1]["loss_MW"]+=0.1),
        x->(x["devices"][end]["eta_ch"]=0.0),
        x->(x["devices"][end]["initial_MWh"]=10.0),
    )
        bad=deepcopy(d)
        mutate(bad)
        @test_throws ErrorException R9TradingCase(bad)
    end
    mktempdir() do dir
        path=joinpath(dir, "case.toml")
        write(path, c.source_text)
        loaded=load_r9_trading_case(path)
        @test loaded.sha256==c.sha256 && loaded.data==c.data
        loaded.data["grid_price"][1]+=1.0
        @test_throws ErrorException build_r9_trading_model(loaded)
    end
end

@testset "R9-T2:T6 analytical power, bidirectional heat and internal accounting" begin
    for reverse in (false, true)
        c=r9_trading_fixture(; reverse)
        r, built=r9_trading_test_solve(c; reverse)
        @test built.model_class=="SOCP" && !any(is_binary, all_variables(built.model))
        @test r["termination"]=="OPTIMAL"
        checked=validate_r9_trading_solution(c, r)
        @test checked["model_pass"] && checked["heat_energy_mass_pass"] && checked["ledger_pass"]
        @test !checked["full_thermal_physics_certified"]
        @test checked["system_cost_CNY"]≈100.0 atol=1e-4
        @test r["values"]["P_grid"][1]≈1.0 atol=1e-6
        sign=reverse ? "minus" : "plus"
        @test all(abs(x[1]-1.0)<=1e-6 for x in r["values"]["H_"*sign*"_out"])
        ledger=r9_trading_ledger(c, r["values"])
        @test abs(ledger["cash_balance_CNY"])<=1e-8
        @test abs(ledger["payoff_identity_CNY"])<=1e-8
        fees=filter(p->p["kind"]=="service", ledger["payments"])
        @test length(fees)==1
        @test only(fees)["amount_CNY"]≈5.0 atol=1e-5
        prices=deepcopy(c.data["settlement"])
        prices["P_peer"].+=20.0
        alt=r9_trading_ledger(c, r["values"]; settlement = prices)
        @test alt["system_cost_CNY"]==ledger["system_cost_CNY"]
        @test alt["actors"][2]["accounting_payoff_CNY"]-ledger["actors"][2]["accounting_payoff_CNY"]≈20.0 atol=1e-5
        plain=r9_trading_ledger(c, r["values"]; p2p = false)
        @test all(p["kind"]!="p2p" && p["kind"]!="service" for p in plain["payments"])
        @test plain["system_cost_CNY"]==ledger["system_cost_CNY"]
        bad=deepcopy(r)
        bad["values"]["H_"*sign*"_out"][1][1]+=0.01
        @test !validate_r9_trading_solution(c, bad)["heat_energy_mass_pass"]
        bad=deepcopy(r)
        bad["input_sha256"]="0"^64
        @test_throws ErrorException validate_r9_trading_solution(c, bad)
        bad=deepcopy(r)
        bad["values"]["ell"][1][1]=20.0
        original=validate_r9_trading_solution(c, bad)
        @test original["model_pass"] && !original["electric_original_pass"]
    end
    d=deepcopy(r9_trading_fixture().data)
    for p in d["heat"]["pipes"]
        p["U_W_mK"]=1.0
        p["loss_MW"]=0.00012
    end
    c=R9TradingCase(d)
    r, _=r9_trading_test_solve(c)
    @test validate_r9_trading_solution(c, r)["heat_energy_mass_pass"]
    @test r["solver_objective"]≈100.024 atol=1e-4
    @test r["values"]["H_gen"][2][1]≈1.00024 atol=1e-6
end

@testset "R9-T3 half-hour storage and independent frozen plans" begin
    c=r9_trading_fixture(; T = 2, dt = 0.5, store = true)
    d=deepcopy(c.data)
    d["grid_price"]=[10.0, 100.0]
    c=R9TradingCase(d)
    r, _=r9_trading_test_solve(c; storage = [1, 0])
    @test r["termination"]=="OPTIMAL"
    v=validate_r9_trading_solution(c, r)
    @test v["model_pass"]
    @test v["system_cost_CNY"]≈10.0 atol=1e-4
    @test r["values"]["E"][end]≈[0.5, 1.0, 0.5] atol=1e-6
    @test r["values"]["P_cons"][end][1]≈1.0 atol=1e-6
    bad=deepcopy(r)
    bad["values"]["E"][end][end]+=0.01
    @test !validate_r9_trading_solution(c, bad)["model_pass"]
    bad=deepcopy(r)
    bad["values"]["P_gen"][end][1]=0.1
    @test !validate_r9_trading_solution(c, bad)["model_pass"]
    c=r9_trading_fixture()
    plans=[first(r9_trading_test_solve(c; stage = :local, actor = i)) for i in 2:3]
    @test all(validate_r9_trading_solution(c, x)["model_pass"] for x in plans)
    r, _=r9_trading_test_solve(c; stage = :network, frozen = plans)
    @test validate_r9_trading_solution(c, r)["model_pass"]
    bad=deepcopy(r)
    bad["frozen_plans"][1]["values"]["P_D"][2][1]+=0.1
    @test !validate_r9_trading_solution(c, bad)["model_pass"]
    @test_throws ErrorException build_r9_trading_model(c; stage = :network)
    @test_throws ErrorException build_r9_trading_model(c; stage = :local, actor = 1)
    @test_throws ErrorException build_r9_trading_model(
        c;
        modes = Dict("z_storage"=>zeros(2, 1), "heat_direction"=>fill(0.5, 2, 1)),
    )
    d=deepcopy(c.data)
    d["devices"][2]["power_max_MW"]=0.5
    d["devices"][2]["availability_MW"]=[0.5]
    impossible=R9TradingCase(d)
    no, _=r9_trading_test_solve(impossible)
    @test no["termination"]=="INFEASIBLE"
    @test !haskey(no, "values") && !validate_r9_trading_solution(impossible, no)["model_pass"]
end
