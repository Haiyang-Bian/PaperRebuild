using Test, PaperRebuild, JuMP, HiGHS

@testset "R5-ST 固定成交价格最优面" begin
    optimizer = optimizer_with_attributes(
        HiGHS.Optimizer,
        "primal_feasibility_tolerance"=>1e-9,
        "dual_feasibility_tolerance"=>1e-9,
    )
    c = load_r5_market_case(joinpath(@__DIR__, "..", "configs", "r5", "market", "wide_line.toml"))
    r = solve_r5_market(c; optimizer, budget_sec = 60)
    @test r["validation"]["kkt_pass"]
    range = r5_market_settlement_range(c, r; optimizer, budget_sec = 60)
    @test range["range_complete"]
    @test range["payment_width_USD"]>1.0
    for (side, e) in range["endpoints"]
        @test e["validation"]["pass"]
        @test e["market_witness"]["values"] == r["values"]
        @test !haskey(e["market_witness"], "raw_duals")
    end
    c1 = load_r5_market_case(joinpath(@__DIR__, "..", "configs", "r5", "market", "hand_hour.toml"))
    r1 = solve_r5_market(c1; optimizer, budget_sec = 60)
    s1 = r5_market_settlement_range(c1, r1; optimizer, budget_sec = 60)
    @test s1["range_complete"]
    @test s1["payment_width_USD"]≈0 atol=1e-6
    @test s1["endpoints"]["minimum"]["payment_USD"]≈600 atol=1e-6
    bad = deepcopy(r1)
    delete!(bad, "multipliers")
    @test_throws ErrorException r5_market_settlement_range(c1, bad; optimizer, budget_sec = 60)
    # 上备用唯一本体且容量恰好用满：sigma和报价上界租金可同增，价格没有有限上限。
    data=deepcopy(c1.data)
    data["generators"][1]["up_max"]=0.0
    data["ies"][1]["up_max"]=20.0
    scarcity=R5MarketCase(data)
    rr=solve_r5_market(scarcity; optimizer, budget_sec = 60)
    @test rr["validation"]["kkt_pass"]
    sr=r5_market_settlement_range(scarcity, rr; optimizer, budget_sec = 60)
    @test !sr["range_complete"]
    @test sr["endpoints"]["minimum"]["termination"]=="DUAL_INFEASIBLE"
    @test sr["endpoints"]["maximum"]["validation"]["pass"]
end
