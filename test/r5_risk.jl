module R5RiskTests
using Test, PaperRebuild, JuMP, HiGHS, Clarabel, TOML

@testset "R5-R transport primal dual and joint event" begin
    opt=optimizer_with_attributes(
        Clarabel.Optimizer,
        "tol_feas"=>1e-10,
        "tol_gap_abs"=>1e-10,
        "tol_gap_rel"=>1e-10,
    )
    p=[0.9, 0.1]
    D=[0.0 1.0; 1.0 0.0]
    for rho in (0.0, 0.05, 0.2, 1.0), q in ([0.0, 1.0], [-5.0, -2.0])
        kind=q==[0.0, 1.0] ? :probability : :cost
        r=r5_worst_distribution(p, D, q, rho; optimizer = opt, quantity = kind)
        @test r["validation"]["pass"]
        expected=q[1]+(q[2]-q[1])*min(1, 0.1+rho)
        @test r["validation"]["primal_value"]≈expected atol=1e-7
        @test sum(r["validation"]["worst_weights"])≈1 atol=1e-8
    end
    # 风险最坏情景与费用最坏情景不同，分别求解才不漏掉风险。
    p3=[0.5, 0.25, 0.25]
    D3=[i==j ? 0.0 : 1.0 for i in 1:3, j in 1:3]
    cost=r5_worst_distribution(p3, D3, [0, 10, 1], 0.1; optimizer = opt)
    risk=r5_worst_distribution(p3, D3, [0, 0, 1], 0.1; optimizer = opt, quantity = :probability)
    @test cost["validation"]["pass"]&&risk["validation"]["pass"]
    @test cost["validation"]["worst_weights"][2]≈0.35 atol=1e-7
    @test risk["validation"]["worst_weights"][3]≈0.35 atol=1e-7
    @test cost["validation"]["worst_weights"][3]<risk["validation"]["worst_weights"][3]-0.09
    zero=r5_worst_distribution(
        [1.0, 0.0],
        D,
        [0.0, 1.0],
        0.1;
        optimizer = opt,
        quantity = :probability,
    )
    @test zero["validation"]["pass"]
    @test zero["validation"]["dual_value"]≈0.1 atol=1e-8
    duplicate=r5_worst_distribution(
        p,
        zeros(2, 2),
        [0.0, 1.0],
        0.0;
        optimizer = opt,
        quantity = :probability,
    )
    @test duplicate["validation"]["dual_value"]≈1.0 atol=1e-8
    @test_throws ErrorException r5_worst_distribution([0.8, 0.1], D, [0, 1], 0.1; optimizer = opt)
    @test_throws ErrorException r5_worst_distribution(
        p,
        [0.0 1.0; 2.0 0.0],
        [0, 1],
        0.1;
        optimizer = opt,
    )
    @test_throws ErrorException r5_worst_distribution(p, D, [0, NaN], 0.1; optimizer = opt)
    @test_throws ErrorException r5_worst_distribution(p, D, [0, 1], -0.1; optimizer = opt)
    bad=deepcopy(risk)
    bad["transport"][1][1]+=0.01
    @test !validate_r5_transport(p3, D3, [0, 0, 1], 0.1, bad; quantity = :probability)["pass"]
    scaled=r5_worst_distribution(p3, 100D3, [0, 10, 1], 10.0; optimizer = opt)
    @test scaled["validation"]["primal_value"]≈cost["validation"]["primal_value"] atol=1e-7
    order=[3, 1, 2]
    perm=r5_worst_distribution(p3[order], D3[order, order], [0, 10, 1][order], 0.1; optimizer = opt)
    @test perm["validation"]["primal_value"]≈cost["validation"]["primal_value"] atol=1e-7
    tiny=r5_worst_distribution(p, D, [0, 1], 0.1; optimizer = opt, budget_sec = 1e-12)
    @test !tiny["validation"]["pass"]
    @test PaperRebuild.r5_risk_termination(MOI.TIME_LIMIT, true)=="time_limit_with_incumbent"
    @test PaperRebuild.r5_risk_termination(MOI.TIME_LIMIT, false)=="time_limit_no_incumbent"
    @test PaperRebuild.r5_risk_termination(MOI.NUMERICAL_ERROR, false)=="NUMERICAL_ERROR"
    @test PaperRebuild.r5_risk_termination(MOI.INFEASIBLE, false)=="solver_infeasible"
end
@testset "R5-R direct MILP and all comfort branches" begin
    root=normpath(joinpath(@__DIR__, "..", "configs", "r5", "risk"))
    highs=optimizer_with_attributes(
        HiGHS.Optimizer,
        "primal_feasibility_tolerance"=>1e-9,
        "dual_feasibility_tolerance"=>1e-9,
        "mip_feasibility_tolerance"=>1e-9,
        "mip_rel_gap"=>1e-9,
    )
    clar=optimizer_with_attributes(
        Clarabel.Optimizer,
        "tol_feas"=>1e-10,
        "tol_gap_abs"=>1e-10,
        "tol_gap_rel"=>1e-10,
    )
    results=Dict{String,Any}()
    for (name, expected) in (
        ("hard_zero", 2.085),
        ("quarter", 0.52125),
        ("hard_r020", 3.505),
        ("hard_r100", 5.5),
        ("thermal_hard", 2.085),
        ("thermal_e025_r000", 1.0626),
        ("thermal_e025_r005", 2.44),
        ("thermal_e030_r005", 1.36648),
        ("thermal_e100_r000", -0.18345),
        ("thermal_e000_r005", 2.44),
    )
        c=load_r5_risk_case(joinpath(root, name*".toml"))
        r=solve_r5_risk(c; optimizer = highs, oracle_optimizer = clar)
        results[name]=r
        @test r["status"]=="solver_optimal"
        @test r["validation"]["model_pass"]&&r["validation"]["risk_pass"]
        @test r["cost_optimization_complete"]
        @test r["validation"]["worst_net_cost"]≈expected atol=1e-6
    end
    c=load_r5_risk_case(joinpath(root, "thermal_e030_r005.toml"))
    m=build_r5_risk(c)
    @test m.model_type=="MILP"&&termination_status(m.model)==MOI.OPTIMIZE_NOT_CALLED
    @test build_r5_risk(c; pattern = [0, 0, 0]).model_type=="continuous_LP"
    enum=solve_r5_risk(c; optimizer = clar, method = :enumeration)
    @test enum["status"]=="enumeration_complete"
    @test enum["validation"]["enumeration"]["complete"]
    @test enum["cost_optimization_complete"]
    @test length(enum["branches"])==8
    @test enum["validation"]["worst_net_cost"]≈results["thermal_e030_r005"]["validation"]["worst_net_cost"] atol=1e-6
    @test count(b->b["status"]=="solver_infeasible", enum["branches"])==5
    relaxed=results["thermal_e025_r000"]
    @test relaxed["validation"]["actual_event"]==[0, 0, 1]
    @test relaxed["validation"]["worst_violation_probability"]≈0.25 atol=1e-8
    @test maximum(relaxed["validation"]["comfort_excess_K"])≈1.0 atol=1e-6
    @test results["thermal_e025_r005"]["validation"]["actual_event"]==[0, 0, 0]
    @test count(
        x->abs(x)<1e-8,
        results["hard_r100"]["validation"]["transport_checks"]["cost"]["worst_weights"],
    )==2
    # 零半径/零违约回到旧共同承诺期望模型；旧接口另行优化。
    hard=load_r5_risk_case(joinpath(root, "hard_zero.toml"))
    old=solve_r5_commitment(R5CommitmentCase(hard.data["commitment"]); optimizer = clar)
    @test old["cost_optimization_complete"]
    @test old["solver_objective"]≈results["hard_zero"]["solver_objective"] atol=1e-6
    bad=load_r5_risk_case(joinpath(root, "physical_infeasible.toml"))
    no=solve_r5_risk(bad; optimizer = highs)
    @test no["status"]=="solver_infeasible"&&!no["cost_optimization_complete"]
    @test !haskey(no, "first_stage")
    # 冻结的末期初温条件不因舒适开关解除。
    for s in values(results["hard_r100"]["scenarios"])
        @test s["values"]["τ_IN"][1][1]≈293.15 atol=1e-4
    end
    d=deepcopy(c.data)
    d["epsilon"]=1.1
    @test_throws ErrorException R5RiskCase(d)
    d=deepcopy(c.data)
    d["temperature_domain"]["building"]["lower_K"]=294.0
    @test_throws ErrorException R5RiskCase(d)
    d=deepcopy(c.data)
    d["commitment"]["scenarios"][2]["case"]["heat"]["pipes"][1]["history_S_K"][1]+=1
    @test_throws ErrorException R5RiskCase(d)
    @test_throws ErrorException build_r5_risk(c; pattern = [0, 1])
    @test_throws ErrorException solve_r5_risk(c; optimizer = highs, budget_sec = -1)
    tiny=solve_r5_risk(c; optimizer = highs, budget_sec = 1e-12)
    @test tiny["status"]=="budget_exhausted_before_solve"&&!tiny["cost_optimization_complete"]
    license=solve_r5_risk(c; optimizer = ()->error("license unavailable"))
    @test license["status"]=="license_unavailable"
    unsupported=solve_r5_risk(c; optimizer = clar)
    @test unsupported["status"]=="unsupported_solver"
    tamper=deepcopy(results["thermal_e030_r005"])
    delete!(tamper["oracles"], "risk")
    @test !validate_r5_risk(c, tamper)["optimality_pass"]
    tamper=deepcopy(results["thermal_e030_r005"])
    tamper["z"].=0
    @test !validate_r5_risk(c, tamper)["model_pass"]
    tamper=deepcopy(enum)
    pop!(tamper["branches"])
    @test !validate_r5_risk(c, tamper)["optimality_pass"]
    mktempdir() do dir
        path=save_r5_risk_run(c, results["thermal_e030_r005"], joinpath(dir, "risk"))
        @test read_r5_risk_run(path).validation["optimality_pass"]
        @test_throws ErrorException save_r5_risk_run(c, results["thermal_e030_r005"], path)
        open(joinpath(path, "result.toml"), "a") do io
            write(io, "\n# altered\n")
        end
        @test_throws ErrorException read_r5_risk_run(path)
        path2=save_r5_risk_run(c, enum, joinpath(dir, "enum"))
        @test read_r5_risk_run(path2).validation["enumeration"]["complete"]
    end
end
end # R5RiskTests
