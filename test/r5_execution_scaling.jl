# 在r5_execution.jl之后读取，复用开放求解器和已验证的父案例。
@testset "R5-EX 单位尺度与选择证书" begin
    p = execution_parent("merit_fixed_bid")
    a = solve_r5_market_execution(
        p.mc;
        lp_optimizer = EX_HIGH,
        qp_optimizer = EX_CLARABEL,
        budget_sec = 60,
    )
    b = solve_r5_market_execution(
        p.mc;
        lp_optimizer = EX_HIGH,
        qp_optimizer = EX_CLARABEL,
        spec = R5MarketExecutionSpec(; quantity_scale_MW = 10, price_scale_USD_MWh = 1000),
        budget_sec = 60,
    )
    @test a["validation"]["execution_pass"] && b["validation"]["execution_pass"]
    for key in keys(a["market"]["values"])
        @test PaperRebuild.r5_market_array(a["market"]["values"][key]) ≈
              PaperRebuild.r5_market_array(b["market"]["values"][key]) atol=1e-5
    end
    @test a["validation"]["payment"]["direct_payment_USD"] ≈
          b["validation"]["payment"]["direct_payment_USD"] atol=1e-4
    data = deepcopy(p.mc.data)
    for kind in ("ies", "generators"),
        actor in data[kind],
        key in ("energy_bid", "up_bid", "down_bid")

        actor[key] .*= 7
    end
    scaled = solve_r5_market_execution(
        R5MarketCase(data);
        lp_optimizer = EX_HIGH,
        qp_optimizer = EX_CLARABEL,
        spec = R5MarketExecutionSpec(; price_scale_USD_MWh = 700),
        budget_sec = 60,
    )
    @test scaled["validation"]["execution_pass"]
    @test scaled["validation"]["payment"]["direct_payment_USD"] ≈
          7*a["validation"]["payment"]["direct_payment_USD"] atol=1e-4
    bad = deepcopy(a)
    delete!(bad["dual"]["witness"], "raw_duals")
    @test !validate_r5_market_execution(p.mc, bad)["execution_pass"]
    @test_throws ErrorException build_r5_execution_selector(p.mc, 0.0; kind = :unknown)
    @test_throws ErrorException build_r5_execution_selector(
        p.mc,
        0.0;
        kind = :primal,
        spec = R5MarketExecutionSpec(; quantity_scale_MW = 1e200),
    )
end
