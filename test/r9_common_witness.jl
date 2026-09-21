module R9CommonWitnessTests
using Test, PaperRebuild, JuMP, HiGHS, TOML
const PR=PaperRebuild
const ROOT=normpath(joinpath(@__DIR__, ".."))
const OPT=optimizer_with_attributes(HiGHS.Optimizer, "threads"=>1)

function small_case()
    d=TOML.parsefile(joinpath(ROOT, "configs/r5/risk/hard_zero.toml"))
    # 只缩小测试对象；正式规模始终读取独立冻结包。
    R5RiskCase(d)
end

@testset "R9-CW1 PV curtailment and restricted infeasibility" begin
    d=deepcopy(small_case().data)
    push!(d["commitment"]["uncertain_fields"], "devices.available_MW")
    for (i, s) in enumerate(d["commitment"]["scenarios"])
        pv=Dict(
            "id"=>"pv",
            "kind"=>"PV",
            "node"=>2,
            "p_min_MW"=>0.0,
            "p_max_MW"=>0.2,
            "q_min_Mvar"=>0.0,
            "q_max_Mvar"=>0.0,
            "cost_USD_MWh"=>0.0,
            "available_MW"=>[0.02i],
        )
        push!(s["case"]["devices"], pv)
    end
    c=R5RiskCase(d)
    before=deepcopy(c.data)
    w=solve_r9_common_witness(c; optimizer = OPT, budget_sec = 30)
    @test w["has_candidate"]
    @test all(abs.(last(w["values"]["P_DER"])) .<= 1e-8)
    @test validate_r5_risk(c, r9_common_risk_candidate(c, w))["model_pass"]
    @test c.data==before
    for s in d["commitment"]["scenarios"]
        last(s["case"]["devices"])["p_min_MW"]=0.01
    end
    impossible=solve_r9_common_witness(R5RiskCase(d); optimizer = OPT, budget_sec = 30)
    @test impossible["status"]=="solver_infeasible"
    @test !impossible["has_candidate"] && !impossible["original_risk_optimality_claim"]
end

@testset "R9-CW2 constant score analytic transport matches LP" begin
    p=[0.2, 0.3, 0.5]
    D=[0.0 0.2 0.5; 0.2 0.0 0.3; 0.5 0.3 0.0]
    for rho in (0.0, 0.01, 0.5), score in (-2.0, 0.0, 7.0)
        q=fill(score, 3)
        r=r9_constant_transport(p, D, q, rho)
        @test r["validation"]["pass"]
        exact=r5_worst_distribution(p, D, q, rho; optimizer = OPT)
        @test exact["validation"]["pass"]
        @test r["validation"]["dual_value"]≈exact["validation"]["dual_value"] atol=1e-8
    end
    @test_throws ErrorException r9_constant_transport(p, D, [0.0, 0.0, 1.0], 0.1)
    @test_throws ErrorException r9_constant_transport(p, D, zeros(3), -1)
    close_scores=[100.0, 100.0+1e-9, 100.0-1e-9]
    bounded=r9_diagonal_transport_bound(p, D, close_scores, 0.01)
    @test bounded["validation"]["pass"] && !bounded["exact_constant_scores"]
    @test bounded["nu"]==fill(maximum(close_scores), 3)
    @test bounded["validation"]["primal_value"]<=bounded["validation"]["dual_value"]
    @test_throws ErrorException r9_diagonal_transport_bound(p, D, [0.0, 100.0, 200.0], 0.01)
end

@testset "R9-CW1 restriction, original replay and no false optimality" begin
    c=small_case()
    before=deepcopy(c.data)
    b=build_r9_common_witness(c)
    @test c.data==before
    @test JuMP.num_variables(b.model)>0
    @test all(!is_binary(v) for v in all_variables(b.model))
    w=solve_r9_common_witness(c; optimizer = OPT, budget_sec = 30)
    @test w["has_candidate"]
    @test w["restriction_residual_MW"]<=1e-8
    @test !w["original_risk_optimality_claim"]
    r=r9_common_risk_candidate(c, w)
    v=validate_r5_risk(c, r)
    @test v["model_pass"] && v["risk_pass"] && v["cost_pass"]
    @test !v["optimality_pass"] && !v["valid_bound"]
    @test !haskey(r, "solver_objective_bound") && !r["cost_optimization_complete"]
    @test c.data==before
    for pattern in (nothing, zeros(Int, length(c.data["commitment"]["scenarios"])))
        full=build_r5_risk(c; pattern)
        start=r9_risk_start_values(c, full, w)
        audit=audit_r9_risk_start(full, start)
        @test audit["pass"] && audit["variables"]==num_variables(full.model)
        @test audit["objective"]≈w["restricted_solver"]["solver_objective"] atol=1e-6
        bad=copy(start)
        bad[index(full.base.first_stage["P_DA_MW"][1]).value]+=0.01
        @test !audit_r9_risk_start(full, bad)["pass"]
    end
    bad=deepcopy(w)
    bad["first_stage"]["R_up_MW"][1]=0.01
    @test_throws ErrorException r9_common_risk_candidate(c, bad)
    bad=deepcopy(w)
    bad["values"]["P_PCC"][1][1]+=0.01
    rr=r9_common_risk_candidate(c, bad)
    @test !validate_r5_risk(c, rr)["model_pass"]
    d=deepcopy(c.data)
    d["commitment"]["day_ahead"]["energy_price"][1]+=1
    @test_throws ErrorException r9_common_risk_candidate(R5RiskCase(d), w)
    d=deepcopy(c.data)
    push!(d["commitment"]["uncertain_fields"], "realtime.price")
    d["commitment"]["scenarios"][1]["case"]["realtime"]["price"][1]+=1
    @test_throws ErrorException build_r9_common_witness(R5RiskCase(d))
    tiny=solve_r9_common_witness(c; optimizer = OPT, budget_sec = 1e-12)
    @test tiny["status"]=="budget_exhausted_before_solve" && !tiny["has_candidate"]
    @test_throws ErrorException r9_common_risk_candidate(c, tiny)
    failed=solve_r9_common_witness(c; optimizer = ()->error("license unavailable"), budget_sec = 10)
    @test failed["status"]=="license_unavailable" && !failed["has_candidate"]
end
end
