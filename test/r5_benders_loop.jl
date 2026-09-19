module R5BendersLoopTests
using Test, PaperRebuild, JuMP, HiGHS, Clarabel, TOML
const root=normpath(joinpath(@__DIR__, "..", "configs", "r5", "risk"))
const opt=optimizer_with_attributes(
    HiGHS.Optimizer,
    "primal_feasibility_tolerance"=>1e-9,
    "dual_feasibility_tolerance"=>1e-9,
    "mip_feasibility_tolerance"=>1e-9,
    "mip_rel_gap"=>1e-9,
)
const oracle=optimizer_with_attributes(
    Clarabel.Optimizer,
    "tol_feas"=>1e-10,
    "tol_gap_abs"=>1e-10,
    "tol_gap_rel"=>1e-10,
)
const hand_runs=Dict{Symbol,Any}()

@testset "R5-BD master domains and full decomposition" begin
    c=load_r5_risk_case(joinpath(root, "hard_zero.toml"))
    m=build_r5_benders_master(c)
    @test m.model_type=="MILP"&&termination_status(m.model)==MOI.OPTIMIZE_NOT_CALLED
    @test m.scope=="full_risk_domain"
    @test_throws ErrorException build_r5_benders_master(c; critical = [1])
    paper=R5BendersSpec(feasibility = :paper_critical)
    @test build_r5_benders_master(c; spec = paper).scope=="restricted_comfort_domain"
    @test build_r5_benders_master(c; spec = paper, critical = [1, 2, 3]).scope=="full_risk_domain"
    for route in (:cuts, :critical, :paper_critical)
        r=solve_r5_benders(
            c;
            optimizer = opt,
            oracle_optimizer = oracle,
            spec = R5BendersSpec(
                feasibility = route,
                cut_arithmetic = :rational_box,
                diagnostic_scale = 1024.0,
            ),
            budget_sec = 60,
        )
        hand_runs[route]=r
        println(
            "hand ",
            route,
            ": ",
            r["status"],
            " iterations=",
            length(r["iterations"]),
            " upper=",
            r["validation"]["upper_bound"],
            " error=",
            get(r, "error", ""),
        )
        @test r["validation"]["evidence_pass"]
        @test r["validation"]["model_pass"]&&r["validation"]["risk_pass"]
        @test r["validation"]["upper_bound"]≈2.085 atol=1e-5
        @test isempty(first(r["iterations"])["master"]["critical"])
        @test isempty(first(r["iterations"])["master"]["cut_source_ids"])
        @test r["source_unchanged"]
        @test validate_r5_benders(c, TOML.parse(PaperRebuild.r5_market_text(r)))["model_pass"]
        if route!=:paper_critical
            @test r["cost_optimization_complete"]&&r["validation"]["stopping_pass"]
            @test r["validation"]["lower_bound"]<=2.085+1e-6
        else
            @test r["validation"]["restricted_stopping_pass"]||r["validation"]["stopping_pass"]
        end
    end
end

@testset "R5-BD risk and negative-cost decomposition" begin
    for name in ("thermal_e030_r005", "hard_r100", "quarter", "future_e030_r005")
        c=load_r5_risk_case(joinpath(root, name*".toml"))
        routes=name=="future_e030_r005" ? (:critical,) : (:cuts, :critical)
        for route in routes
            r=solve_r5_benders(
                c;
                optimizer = opt,
                oracle_optimizer = oracle,
                spec = R5BendersSpec(
                    feasibility = route,
                    cut_arithmetic = :rational_box,
                    diagnostic_scale = 1024.0,
                ),
                budget_sec = 60,
            )
            println(
                name,
                " ",
                route,
                ": ",
                r["status"],
                " iterations=",
                length(r["iterations"]),
                " upper=",
                r["validation"]["upper_bound"],
                " error=",
                get(r, "error", ""),
            )
            @test r["validation"]["model_pass"]&&r["validation"]["risk_pass"]
            @test r["cost_optimization_complete"]
            # 独立参照在分解运行后另解，不进入其输入、初值或割。
            direct=solve_r5_risk(c; optimizer = opt, oracle_optimizer = oracle, budget_sec = 60)
            @test direct["cost_optimization_complete"]
            gap=abs(r["validation"]["upper_bound"]-direct["validation"]["worst_net_cost"])/max(
                1,
                abs(direct["validation"]["worst_net_cost"]),
            )
            @test gap<=1e-4
        end
    end
end

@testset "R5-BD exact encoded cuts and equivalent scaling" begin
    c=load_r5_risk_case(joinpath(root, "hard_zero.toml"))
    @test_throws ErrorException R5BendersSpec(diagnostic_scale = 3.0)
    @test_throws ErrorException R5BendersSpec(cut_arithmetic = :unknown)
    @test PaperRebuild.r5_benders_spec(
        Dict(
            "feasibility"=>"cuts",
            "critical_count"=>1,
            "max_iterations"=>200,
            "absolute_gap"=>1e-7,
            "relative_gap"=>1e-6,
        ),
    ).diagnostic_scale==1.0
    R=PaperRebuild.r5_benders_rational
    @test R(PaperRebuild.r5_benders_outward(1//10, :down))<=1//10
    @test R(PaperRebuild.r5_benders_outward(1//10, :up))>=1//10
    x=Dict("P_DA_MW"=>[0.9], "R_up_MW"=>[0.0], "R_down_MW"=>[0.0])
    rr=solve_r5_benders_subproblem(
        c,
        3,
        x;
        elastic = true,
        optimizer = opt,
        numerical_scale = 1024.0,
    )
    @test rr["validation"]["kkt_pass"]
    @test rr["solver_objective"]≈(0.9-0.142)/2 atol=1e-10
    @test rr["raw_duals"]==Dict(k=>1024*v for (k, v) in rr["solver_raw_duals"])
    @test all(v>=-1e-12 for (k, v) in rr["flat_values"] if startswith(k, "elastic/"))
    q=r5_benders_cut(c, rr; arithmetic = :rational_box)
    @test q["constant"]≈-0.071 atol=1e-12
    @test q["rounding_guard"]<1e-12
    @test q["productive"]
    # 手算吸收能力P+D<=0.142。检查整个声明盒内的解析诊断下界，而非只检查来源点。
    for p in (0.0, 0.08, 0.142, 0.6, 1.0), d in (0.0, 0.062, 0.08)
        trial=Dict("P_DA_MW/1"=>p, "R_up_MW/1"=>0.0, "R_down_MW/1"=>d)
        @test PaperRebuild.r5_benders_affine(q, trial)<=max(0.0, (p+d-0.142)/2)+1e-13
    end
    bad=deepcopy(rr)
    bad["solver_raw_duals"][first(keys(bad["solver_raw_duals"]))]+=1
    @test !validate_r5_benders_subproblem(c, bad)["kkt_pass"]
    bad=deepcopy(rr)
    bad["solver_raw_values"]["P_PCC/1/1"]+=1
    @test !validate_r5_benders_subproblem(c, bad)["kkt_pass"]
end

@testset "R5-BD history scope persistence and failure propagation" begin
    c=load_r5_risk_case(joinpath(root, "hard_zero.toml"))
    r=hand_runs[:cuts]
    # 受限域不能冒充完整域：即使这个手算例恰巧取得相同费用。
    restricted=hand_runs[:paper_critical]
    @test !restricted["cost_optimization_complete"]
    @test restricted["validation"]["lower_bound"]==-Inf
    bad=deepcopy(restricted)
    bad["status"]="full_domain_gap"
    @test_throws ErrorException validate_r5_benders(c, bad)
    bad=deepcopy(r)
    bad["status"]="full_domain_infeasible"
    @test_throws ErrorException validate_r5_benders(c, bad)
    bad=deepcopy(r)
    bad["cuts"][first(bad["cut_order"])]["constant"]+=1
    @test_throws ErrorException validate_r5_benders(c, bad)
    bad=deepcopy(r)
    bad["iterations"][end]["gap"]["relative"]=0.9
    @test_throws ErrorException validate_r5_benders(c, bad)
    bad=deepcopy(r)
    bad["selected_iteration"]=1
    @test_throws ErrorException validate_r5_benders(c, bad)
    mktempdir() do dir
        path=save_r5_benders_run(c, r, joinpath(dir, "run"))
        replay=read_r5_benders_run(path)
        @test replay.validation["stopping_pass"]
        @test replay.result["run_id"]==r["run_id"]
        @test_throws ErrorException save_r5_benders_run(c, r, path)
        @test compare_r5_benders_runs(path, path)["a2_pass"]
        project=normpath(joinpath(@__DIR__, ".."))
        output=read(
            `$(Base.julia_cmd()) --startup-file=no --project=$project $(joinpath(path,"code","replay.jl"))`,
            String,
        )
        @test occursin("model=true optimal=true", output)
        write(
            joinpath(path, "result.toml"),
            read(joinpath(path, "result.toml"), String)*"\n# altered\n",
        )
        @test_throws ErrorException read_r5_benders_run(path)
    end
    tiny=solve_r5_benders(c; optimizer = opt, budget_sec = 1e-12)
    @test tiny["status"]=="budget_exhausted"&&!tiny["validation"]["model_pass"]
    @test isempty(tiny["iterations"])
    missing=solve_r5_benders(c; optimizer = ()->error("license unavailable"))
    @test missing["status"]=="license_unavailable"&&!missing["cost_optimization_complete"]
    unsupported=solve_r5_benders(c; optimizer = oracle, budget_sec = 60)
    @test unsupported["status"]=="unsupported_solver"&&!unsupported["validation"]["model_pass"]
    calls=Ref(0)
    function late_failure()
        calls[]+=1
        calls[]>3&&error("license unavailable in later subproblem")
        MOI.instantiate(opt)
    end
    failed=solve_r5_benders(
        c;
        optimizer = opt,
        subproblem_optimizer = late_failure,
        oracle_optimizer = oracle,
        budget_sec = 60,
    )
    @test failed["status"]=="untrusted_or_unresolved_subproblem"
    @test failed["validation"]["model_pass"]&&!failed["cost_optimization_complete"]
    @test failed["selected_iteration"]==1
    @test all(s["status"]=="license_unavailable" for s in failed["failure_sources"])
    @test validate_r5_benders(c, TOML.parse(PaperRebuild.r5_market_text(failed)))["evidence_pass"]
    capped=solve_r5_benders(
        c;
        optimizer = opt,
        oracle_optimizer = oracle,
        spec = R5BendersSpec(max_iterations = 1),
        budget_sec = 60,
    )
    @test capped["status"]=="iteration_limit"&&capped["validation"]["model_pass"]
    @test !capped["cost_optimization_complete"]
    impossible=load_r5_risk_case(joinpath(root, "physical_infeasible.toml"))
    infeasible=solve_r5_benders(
        impossible;
        optimizer = opt,
        oracle_optimizer = oracle,
        budget_sec = 60,
    )
    @test infeasible["status"]=="full_domain_infeasible"
    @test !infeasible["validation"]["model_pass"]
    @test infeasible["validation"]["infeasibility_scope"]=="solver_reported_full_domain"
end
end
