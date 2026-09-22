module R5MarketPaymentTests
using Test, PaperRebuild, JuMP, HiGHS, Clarabel
const RP=PaperRebuild
root=normpath(joinpath(@__DIR__, ".."))
highs=optimizer_with_attributes(
    HiGHS.Optimizer,
    "primal_feasibility_tolerance"=>1e-9,
    "dual_feasibility_tolerance"=>1e-9,
)
clarabel=optimizer_with_attributes(
    Clarabel.Optimizer,
    "tol_feas"=>1e-10,
    "tol_gap_abs"=>1e-10,
    "tol_gap_rel"=>1e-10,
)
@testset "R5-SP 全时域支付与强对偶线性式" begin
    for solver in (highs, clarabel),
        file in
        ("hand_hour", "hand_quarter", "two_bus", "wide_line", "bid_cap", "ramp_memory", "no_ies")

        c=load_r5_market_case(joinpath(root, "configs", "r5", "market", file*".toml"))
        r=solve_r5_market(c; optimizer = solver, budget_sec = 60)
        pay=r5_market_payment_identity(c, r)
        @test pay["valid_for_reformulation"]
        @test pay["direct_payment_USD"]≈pay["affine_payment_USD"] atol=pay["identity_tolerance_USD"]
        @test pay["scope"]=="all_IES_whole_horizon"
        if file=="hand_hour"
            @test pay["direct_payment_USD"]≈600 atol=1e-5
            # 原5-59从5-34移项后应同时减去发电能量和两种备用报价成本。
            terms=pay["linear_terms_USD"]
            generator_total=terms["generator_energy"]+terms["generator_up"]+terms["generator_down"]
            correct=r["solver_objective"]-generator_total
            printed=r["solver_objective"]-(
                terms["generator_energy"]-terms["generator_up"]-terms["generator_down"]
            )
            @test correct≈-3000 atol=1e-5
            @test printed-correct≈240 atol=1e-5
            bad=deepcopy(r)
            bad["multipliers"]["energy"][1]+=1
            @test !r5_market_payment_identity(c, bad)["valid_for_reformulation"]
            bad=deepcopy(r)
            bad["raw_duals"]["energy"][1]+=1
            @test r5_market_payment_identity(c, bad)["identity_pass"]
            @test !r5_market_payment_identity(c, bad)["valid_for_reformulation"]
            nodual=deepcopy(r)
            delete!(nodual, "multipliers")
            @test !r5_market_payment_identity(c, nodual)["identity_pass"]
        elseif file=="hand_quarter"
            @test pay["direct_payment_USD"]≈150 atol=1e-5
        elseif file=="no_ies"
            @test pay["direct_payment_USD"]==0.0
        elseif file=="bid_cap"
            @test abs(pay["linear_terms_USD"]["generator_bid_capacity"])>1
        end
    end
    c=load_r5_market_case(joinpath(root, "configs", "r5", "market", "hand_hour.toml"))
    d=deepcopy(c.data)
    second=deepcopy(only(d["ies"]))
    second["id"]="IES2"
    push!(d["ies"], second)
    multi=R5MarketCase(d)
    r=solve_r5_market(multi; optimizer = highs)
    pay=r5_market_payment_identity(multi, r)
    @test pay["valid_for_reformulation"]
    @test pay["direct_payment_USD"]≈1200 atol=1e-5
    @test sum(sum(x) for x in pay["payment_by_IES_USD"])≈1200 atol=1e-5
    failed=solve_r5_market(c; optimizer = highs, budget_sec = 1e-9)
    @test !r5_market_payment_identity(c, failed)["valid_for_reformulation"]
    # 非零初始出力且首时段爬坡活跃：省略r_1*p_0会恰好漏900美元。
    ramp=deepcopy(
        load_r5_market_case(joinpath(root, "configs", "r5", "market", "ramp_memory.toml")).data,
    )
    ramp["T"]=1
    ramp["load_MW"]=[[100.0]]
    ramp["reserve_up_MW"]=[0.0]
    ramp["reserve_down_MW"]=[0.0]
    ramp["generators"][1]["p_initial"]=30.0
    for g in ramp["generators"], k in ("energy_bid", "up_bid", "down_bid")
        g[k]=[first(g[k])]
    end
    c0=R5MarketCase(ramp)
    r0=solve_r5_market(c0; optimizer = highs)
    p0=r5_market_payment_identity(c0, r0)
    @test p0["valid_for_reformulation"]
    @test p0["linear_terms_USD"]["ramp_initial"]≈900 atol=1e-6
    @test p0["affine_payment_USD"]≈0 atol=1e-6
end
end
