using Test, PaperRebuild, JuMP, HiGHS, Clarabel, TOML

const EX_HIGH = optimizer_with_attributes(
    HiGHS.Optimizer,
    "primal_feasibility_tolerance"=>1e-9,
    "dual_feasibility_tolerance"=>1e-9,
    "mip_feasibility_tolerance"=>1e-9,
    "mip_rel_gap"=>1e-9,
)
const EX_CLARABEL = optimizer_with_attributes(
    Clarabel.Optimizer,
    "tol_feas"=>1e-10,
    "tol_gap_abs"=>1e-10,
    "tol_gap_rel"=>1e-10,
)
function execution_parent(name)
    w = TOML.parsefile(
        joinpath(
            @__DIR__,
            "..",
            "results",
            "summaries",
            "r5-strategic",
            "witnesses",
            name*"-sos1.toml",
        ),
    )
    c = R5StrategicCase(w["case"])
    mc = PaperRebuild.r5_strategic_market_case(c, w["result"]["bids"])
    (; c, mc, result = w["result"])
end

@testset "R5-EX 严格凸选择与原始乘子" begin
    for active in (false, true)
        m = Model(EX_CLARABEL)
        @variable(m, x>=0)
        @variable(m, y>=0)
        @constraint(m, x+y==1)
        if active
            @constraint(m, x>=0.8)
            @constraint(m, y<=0.2)
        end
        @objective(m, Min, 0.5*(x^2+y^2))
        b = (; model = m, variables = [x, y], h = ones(2))
        status = PaperRebuild.r5_risk_optimize!(m, time()+30)
        w = PaperRebuild.r5_execution_qp_witness(b)
        @test status["status"]=="solver_optimal"
        @test PaperRebuild.r5_execution_qp_check(w)["pass"]
        @test value(x)≈(active ? 0.8 : 0.5) atol=1e-6
        @test value(y)≈(active ? 0.2 : 0.5) atol=1e-6
        bad = deepcopy(w)
        bad["raw_duals"][1]+=1
        @test !PaperRebuild.r5_execution_qp_check(bad)["pass"]
        @test !PaperRebuild.r5_execution_qp_check(Dict())["pass"]
    end
    @test_throws ErrorException R5MarketExecutionSpec(; quantity_scale_MW = 0)
    @test_throws ErrorException R5MarketExecutionSpec(; price_scale_USD_MWh = Inf)
end

@testset "R5-EX 市场唯一选择与固定交付" begin
    for (name, expected) in
        (("competitive_hard_zero", 0.0), ("merit_strategic", 0.0), ("merit_fixed_bid", 0.1))
        p = execution_parent(name)
        r = solve_r5_market_execution(
            p.mc;
            lp_optimizer = EX_HIGH,
            qp_optimizer = EX_CLARABEL,
            budget_sec = 60,
        )
        @test r["status"]=="selection_solved"
        @test r["validation"]["execution_pass"]
        @test only(r["market"]["values"]["P_IES"])[1]≈expected atol=1e-5
        @test !haskey(r["market"], "raw_duals")
        @test r["validation"]["payment"]["identity_pass"]
        # 相同报价下的旧乐观成交另行固定，条件费用应恢复原值。
        delivery = evaluate_r5_execution_delivery(
            p.c,
            p.mc,
            p.result["selected_market"];
            optimizer = EX_HIGH,
            oracle_optimizer = EX_HIGH,
            budget_sec = 60,
        )
        @test delivery["validation"]["delivery_pass"]
        @test delivery["validation"]["cost_complete"]
        @test delivery["validation"]["total_cost_USD"] ≈
              validate_r5_strategic(p.c, p.result)["worst_total_cost_USD"] atol=1e-5
        @test delivery["validation"]["bound_scope"]=="fixed_bids_and_executed_awards_only"
        if name=="merit_fixed_bid"
            actual = evaluate_r5_execution_delivery(
                p.c,
                p.mc,
                r["market"];
                optimizer = EX_HIGH,
                oracle_optimizer = EX_HIGH,
                budget_sec = 60,
            )
            @test actual["validation"]["delivery_pass"]
            @test actual["validation"]["total_cost_USD"]≈15.46 atol=1e-4
            impossible = evaluate_r5_execution_delivery(
                p.c,
                p.mc,
                p.result["independent_market"];
                optimizer = EX_HIGH,
                oracle_optimizer = EX_HIGH,
                budget_sec = 60,
            )
            @test impossible["status"]=="solver_infeasible"
            @test !impossible["validation"]["delivery_pass"]
        end
        bad = deepcopy(r)
        bad["market"]["values"]["P_IES"][1][1]+=0.01
        @test_throws ErrorException validate_r5_market_execution(p.mc, bad)
        bad = deepcopy(r)
        bad["primal"]["witness"]["system"]["h"][1]*=2
        @test_throws ErrorException validate_r5_market_execution(p.mc, bad)
        mktempdir() do dir
            out = joinpath(dir, "execution")
            payload = Dict("kind"=>"market_execution", "case"=>p.mc.data)
            save_r5_execution_run(payload, r, out)
            @test read_r5_execution_run(out).validation["execution_pass"]
            @test_throws ErrorException save_r5_execution_run(payload, r, out)
            open(joinpath(out, "result.toml"), "a") do io
                println(io, "# tampered")
            end
            @test_throws ErrorException read_r5_execution_run(out)
            od = joinpath(dir, "delivery")
            pd = Dict(
                "kind"=>"fixed_award_delivery",
                "case"=>p.c.data,
                "market_case"=>p.mc.data,
                "market"=>p.result["selected_market"],
            )
            save_r5_execution_run(pd, delivery, od)
            @test read_r5_execution_run(od).validation["delivery_pass"]
        end
    end
    p = execution_parent("competitive_hard_zero")
    timeout = solve_r5_market_execution(
        p.mc;
        lp_optimizer = EX_HIGH,
        qp_optimizer = EX_CLARABEL,
        budget_sec = 1e-12,
    )
    @test !timeout["validation"]["execution_pass"]
    @test occursin("budget_exhausted", timeout["status"])
end
