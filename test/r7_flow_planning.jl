using Test, PaperRebuild, JuMP, HiGHS, TOML
include("r7_flow_planning_fixtures.jl")

@testset "R7 shared continuous normal and recovery flow" begin
    opt=optimizer_with_attributes(
        HiGHS.Optimizer,
        "threads"=>1,
        "primal_feasibility_tolerance"=>1e-9,
        "dual_feasibility_tolerance"=>1e-9,
        "mip_feasibility_tolerance"=>1e-9,
        "mip_rel_gap"=>1e-9,
    )
    @testset "R7-J1/J3 zero flow retains spatial memory" begin
        m=Model(opt)
        set_silent(m)
        out=@variable(m, [1:3], lower_bound=0, upper_bound=1)
        inv=@variable(m, [1:4], lower_bound=0, upper_bound=1)
        add_r7_mass_transport!(
            m,
            [0.3, 0.0, 0.4],
            [1.0, 0.0, 1.0],
            out,
            inv,
            [1.0],
            [0.0];
            allow_zero = true,
        )
        @objective(m, Min, 0)
        optimize!(m)
        @test termination_status(m)==MOI.OPTIMAL
        @test value.(inv)≈[0.0, 0.3, 0.3, 0.7] atol=1e-9
        @test value(out[1])≈0 atol=1e-9
        @test value(out[3])≈0 atol=1e-9
        @test_throws ErrorException add_r7_mass_transport!(
            Model(),
            [0.0],
            [0.0],
            [0.0],
            [0.0, 0.0],
            [1.0],
            [0.0],
        )
        @test_throws ErrorException add_r7_mass_transport!(
            Model(),
            [-0.1],
            [0.0],
            [0.0],
            [0.0, 0.0],
            [1.0],
            [0.0];
            allow_zero = true,
        )
        @test_throws ErrorException PaperRebuild.r7_affine_interval(Inf)
        @test_throws ErrorException PaperRebuild.r7_affine_interval(@variable(m, lower_bound=0))
    end
    c, s=joint_test_case()
    @testset "R7-J2 fixed degeneration and all fault inheritance" begin
        @test build_r7_flow_planning(c, s).model_class=="MILP"
        r=solve_r7_flow_planning(c, s; optimizer = opt, budget_sec = 60)
        @test r["candidate_accepted"]
        @test r["domain_cost_complete"]
        @test r["validation"]["cost_USD"]≈193.275 atol=1e-5
        @test length(r["validation"]["witness_checks"])==4
        @test all(w["thermal"]["same_dispatch_pass"] for w in r["validation"]["witness_checks"])
        # 错误边界不能靠恢复原值仍满足其自身模型蒙混过关。
        bad=deepcopy(r)
        boundary=bad["witnesses"][1]["boundary_values"]
        x=PaperRebuild.r7_unpack(boundary, "m_normal")
        x[1]+=0.1
        boundary["m_normal"]=PaperRebuild.r7_pack(x)
        @test !validate_r7_flow_planning(c, s, bad)["robust_model_pass"]
        bad=deepcopy(r)
        pop!(bad["witnesses"])
        @test_throws ErrorException validate_r7_flow_planning(c, s, bad)
        bad=deepcopy(r)
        bad["witnesses"][1]["lower_bound_MWh"]=0.0
        @test_throws ErrorException validate_r7_flow_planning(c, s, bad)
        mktempdir() do dir
            target=joinpath(dir, "record")
            save_r7_flow_planning(c, s, r, target)
            @test read_r7_flow_planning(target).validation["robust_model_pass"]
            @test_throws ErrorException save_r7_flow_planning(c, s, r, target)
            open(joinpath(target, "result.toml"), "a") do io
                write(io, "\n# tampered\n")
            end
            @test_throws ErrorException read_r7_flow_planning(target)
        end
    end
    @testset "R7-J1/J4 failures remain explicit" begin
        bad=deepcopy(s)
        pop!(bad["bounds"])
        @test_throws ErrorException build_r7_flow_planning(c, bad)
        @test_throws ErrorException build_r7_flow_planning(c, s; deadline = time()-1)
        r=solve_r7_flow_planning(c, s; optimizer = opt, budget_sec = 0)
        @test r["status"]=="budget_exhausted"
        @test !r["candidate_accepted"]
        r=solve_r7_flow_planning(
            c,
            s;
            optimizer = ()->error("license unavailable"),
            budget_sec = 60,
        )
        @test r["status"]=="license_unavailable"
        c0, s0=joint_test_case(; limit = 0.0)
        r=solve_r7_flow_planning(c0, s0; optimizer = opt, budget_sec = 60)
        @test r["status"]=="infeasible_certified"
        @test !r["candidate_accepted"]
        cf, sf=joint_test_case(; free_normal = true, free_recovery = true)
        b=build_r7_flow_planning(cf, sf)
        @test b.model_class=="nonconvex_MIQCP"
        @test all(size(a)==(size(a, 1), 4) for a in values(b.normal_flow))
        @test all(size(w.variables["m_pipe"])==(1, 1) for w in b.recovery)
        r=solve_r7_flow_planning(cf, sf; optimizer = opt, budget_sec = 60)
        @test r["status"]=="solver_error"
        @test !r["candidate_accepted"]
    end
end
