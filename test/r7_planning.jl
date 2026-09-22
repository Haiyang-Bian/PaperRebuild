using Test, PaperRebuild, JuMP, HiGHS, Clarabel, TOML, SHA

@testset "R7 finite-fault planning" begin
    root=normpath(joinpath(@__DIR__, ".."))
    c=load_r7_planning_case(
        joinpath(root, "configs/r7/normal-reserve-hand.toml"),
        joinpath(root, "configs/r7/planning-reserve-hand.toml"),
    )
    old=load_r7_planning_case(
        joinpath(root, "configs/r7/normal-hand.toml"),
        joinpath(root, "configs/r7/planning-hand.toml"),
    )
    opt=optimizer_with_attributes(
        HiGHS.Optimizer,
        "threads"=>1,
        "primal_feasibility_tolerance"=>1e-9,
        "dual_feasibility_tolerance"=>1e-9,
        "mip_feasibility_tolerance"=>1e-9,
        "mip_rel_gap"=>1e-9,
    )
    @testset "R7-M1 shared normal variables and exact affine blocks" begin
        b=build_r7_planning(c)
        @test length(b.recovery)==4
        @test b.model_class=="MILP"
        @test all(F in (VariableRef, AffExpr) for (F, _) in list_of_constraint_types(b.model))
        @test length(build_r7_planning(c; included = []).recovery)==0
        @test_throws ErrorException build_r7_planning(c; included = [(event = 3, fault = [0])])
        @test_throws ErrorException build_r7_planning(
            c;
            included = [(event = 1, fault = [1]), (event = 1, fault = [1])],
        )
        # 复制器必须保留全部标量集合/常量；拒绝不支持的二次约束，不做近似复制。
        a=Model()
        @variable(a, 0<=x<=2)
        @constraint(a, 2x+3>=5)
        @objective(a, Min, 4x+7)
        target=Model(opt)
        set_silent(target)
        z=PaperRebuild.r7_append_linear_block!(target, a, "analytic")
        @objective(target, Min, z.objective)
        optimize!(target)
        @test objective_value(target)≈11 atol=1e-9
        @test value(z.variables[x])≈1 atol=1e-9
        @constraint(a, x^2<=3)
        @test_throws ErrorException PaperRebuild.r7_append_linear_block!(Model(), a, "quadratic")
    end
    normal=solve_r7_normal(c.normal; optimizer = opt, budget_sec = 60)
    ex=solve_r7_planning(c; optimizer = opt, method = :extensive, budget_sec = 60)
    cc=solve_r7_planning(c; optimizer = opt, method = :finite_fault_ccg, budget_sec = 60)
    @testset "R7-M2 analytical reserve cost and extensive reference" begin
        @test normal["candidate_accepted"]
        @test normal["solver_objective_USD"]≈192.0 atol=1e-6
        for r in (ex, cc)
            @test r["candidate_accepted"]
            @test r["conditional_cost_complete"]
            @test r["validation"]["cost_USD"]≈193.275 atol=1e-6
            @test !r["full_preplan_optimality_verified"]
            @test !r["author_nested_algorithm_verified"]
            idx=r["validation"]["candidate_iteration"]
            n=r["iterations"][idx]["master"]["normal"]
            energy=PaperRebuild.r7_unpack(n["values"], "E_BES")
            @test all(isapprox.(energy[2, 2:3, :], 0.8; atol = 1e-6))
            @test !haskey(n, "lower_bound_USD")
            @test !validate_r7_normal(c.normal, n)["optimality_pass"]
        end
        @test ex["validation"]["cost_USD"]≈cc["validation"]["cost_USD"] atol=1e-6
        # 有限拓扑逐LP是不同求解路径，检查最终每个事件的全部故障。
        n=cc["iterations"][end]["master"]["normal"]
        for s in 1:2
            ev=PaperRebuild.r7_planning_event(c, n, s)
            for gamma in r7_faults(ev.case)
                er=enumerate_r7_recovery(ev.case, gamma; optimizer = opt, budget_sec = 60)
                @test er["gap_certified"]
                @test abs(er["upper_bound_MWh"])<=1e-6
            end
        end
        # 连续固定模式解可由无商业许可锥求解器核对，不伪造缺失的目标界。
        ev=PaperRebuild.r7_planning_event(c, n, 1)
        lp=solve_r7_recovery(
            ev.case,
            [1];
            optimizer = Clarabel.Optimizer,
            fixed_z = [0],
            budget_sec = 60,
        )
        @test lp["candidate_accepted"]
        @test abs(lp["validation"]["loss_MWh"])<=1e-6
    end
    @testset "R7-M3 event certificates reset and bound directions" begin
        @test length(cc["iterations"])>=2
        ids=[it["master"]["normal"]["run_id"] for it in cc["iterations"]]
        @test length(unique(ids))==length(ids)
        @test any(!isempty(it["added_pairs"]) for it in cc["iterations"])
        @test all(length(it["audits"])==2 for it in cc["iterations"])
        @test all(
            a["oracle"]["status"]=="safe_adopted_model" for a in cc["iterations"][end]["audits"]
        )
        fake=deepcopy(cc)
        fake["iterations"][end]["audits"][1]=deepcopy(fake["iterations"][1]["audits"][1])
        @test_throws ErrorException validate_r7_planning(c, fake)
        # 健康内部线也可能违反灾害门槛，不能假设[0]一定不是已认证反例。
        fake=deepcopy(cc)
        fake["iterations"][1]["added_pairs"][1]["fault"]=[2]
        @test_throws ErrorException validate_r7_planning(c, fake)
        fake=deepcopy(cc)
        fake["iterations"][1]["audits"][1]["oracle"]["upper_bound_MWh"]=0.0
        @test_throws ErrorException validate_r7_planning(c, fake)
        # 恢复见证不提供最小失供界；防止把主问题成本界冒充子模型界。
        fake=deepcopy(ex)
        fake["iterations"][1]["master"]["normal"]["lower_bound_USD"]=193.275
        @test_throws ErrorException validate_r7_planning(c, fake)
    end
    @testset "R7-M4 infeasible inherited CHP and failure evidence" begin
        for method in (:extensive, :finite_fault_ccg)
            r=solve_r7_planning(old; optimizer = opt, method, budget_sec = 60)
            @test r["status"]=="infeasible_certified"
            @test !r["candidate_accepted"]
            @test !r["conditional_cost_complete"]
            @test !haskey(r["validation"], "cost_USD")
        end
        zero=solve_r7_planning(c; optimizer = opt, budget_sec = 0)
        @test zero["status"]=="budget_exhausted"
        @test isempty(zero["iterations"])
        @test !zero["candidate_accepted"]
        event=PaperRebuild.r7_event_template(c, 1)
        expired=audit_r7_faults(event; optimizer = opt, budget_sec = 60, deadline = time()-1)
        @test isempty(expired["runs"])
        @test expired["status"]=="unresolved"
        @test expired["upper_bound_MWh"]==Inf
        missing_license=()->error("license unavailable fixture")
        err=solve_r7_planning(c; optimizer = missing_license, budget_sec = 60)
        @test err["status"]=="license_unavailable"
        @test !err["candidate_accepted"]
        @test_throws ErrorException solve_r7_planning(c; optimizer = opt, budget_sec = -1)
        @test_throws ErrorException solve_r7_planning(c; optimizer = opt, method = :nested_claim)
        changed=deepcopy(c)
        changed.specification["events"][1]["loss_limit_MWh"]=1.0
        @test_throws ErrorException build_r7_planning(changed)
    end
    @testset "R7-M5 immutable evidence and independent revalidation" begin
        mktempdir() do dir
            dest=joinpath(dir, "run")
            save_r7_planning(c, cc, dest)
            again=read_r7_planning(dest)
            @test again.validation["robust_model_pass"]
            @test isequal(again.result, cc)
            @test_throws ErrorException save_r7_planning(c, cc, dest)
            open(io->write(io, "# tampered\n"), joinpath(dest, "result.toml"), "a")
            @test_throws ErrorException read_r7_planning(dest)
        end
        fake=deepcopy(cc)
        fake["candidate_accepted"]=false
        @test_throws ErrorException PaperRebuild.r7_planning_check_record(c, fake)
        fake=deepcopy(ex)
        w=fake["iterations"][1]["master"]["witnesses"][1]
        w["witness_loss_MWh"]+=0.1
        @test !validate_r7_planning(c, fake)["robust_model_pass"]
        frozen=TOML.parsefile(joinpath(root, "configs/r7/reserve-hand-freeze.toml"))
        @test frozen["frozen_before_optimization"]
        for (p, hash) in frozen["files"]
            @test bytes2hex(sha256(read(joinpath(root, p))))==hash
        end
    end
end
