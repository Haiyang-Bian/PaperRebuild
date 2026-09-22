using Test, JuMP, Clarabel, TOML

@testset "R4 distributed convex coordination and bilateral consensus" begin
    c=load_r4_case(joinpath(@__DIR__, "..", "configs", "r4", "baseline", "open_flexible.toml"))
    opt=optimizer_with_attributes(
        Clarabel.Optimizer,
        "tol_feas"=>1e-9,
        "tol_gap_abs"=>1e-9,
        "tol_gap_rel"=>1e-9,
    )
    modes=[1, 0, 1, 0]
    @test_throws ErrorException R4DistributedSpec(rho = 0)
    @test_throws ErrorException R4DistributedSpec(peer_rho = NaN)
    @test_throws ErrorException R4DistributedSpec(max_iterations = 0)
    @test_throws ErrorException build_r4_distributed_block(c; actor = 2, modes = nothing)
    @test_throws ErrorException build_r4_distributed_block(c; actor = 1, modes, purpose = :agnb)
    a=build_r4_distributed_block(c; actor = 2, modes)
    n=build_r4_distributed_block(c; actor = 1, modes)
    @test !haskey(a.variables, "P_grid")
    @test haskey(n.variables, "P_interface")
    @test size(a.message)==(4, 4)
    @test size(n.message)==(8, 4)
    @test n.base.model_class=="SOCP"
    @test all(!is_binary(x) for x in all_variables(a.model))
    @test termination_status(n.model)==MOI.OPTIMIZE_NOT_CALLED
    # 带非零最优交易的解析二次例，验证方向与缩放乘子；qA=2,qB=-2。
    z=[zeros(1, 1), zeros(1, 1)]
    u=deepcopy(z)
    for k in 1:80
        q=[(fill(1.0, 1, 1)+2(z[1]-u[1]))/3, (fill(-3.0, 1, 1)+2(z[2]-u[2]))/3]
        z=collect(PaperRebuild.r4_peer_consensus(q[1], q[2], u[1], u[2]))
        u=[u[j]+q[j]-z[j] for j in 1:2]
    end
    @test z[1][1]≈2 atol=1e-10
    @test z[2][1]≈-2 atol=1e-10
    @test 2u[1][1]≈-1 atol=1e-10
    @test 2u[2][1]≈-1 atol=1e-10
    sw=solve_r4_distributed(c; optimizer = opt, modes, budget_sec = 60)
    @test sw["status"]=="consensus_converged"
    @test sw["validation"]["model_pass"]
    @test sw["validation"]["consensus_A4_pass"]
    ref=PaperRebuild.r4_solve_stage(c, R4Spec(), opt, time()+60; build_options = (; modes))
    @test validate_r4_solution(c, ref)["model_pass"]
    @test ref["relative_gap"]<=1e-4
    @test abs(sw["candidate"]["operating_cost"]-ref["solver_objective"])/max(
        1,
        abs(ref["solver_objective"]),
    )<=1e-3
    # 固定完整边界，把同一集中可行点嵌入运营商块；比较DSO自身成本，不混入AG成本。
    op=build_r4_distributed_block(c; actor = 1, modes, optimizer = opt)
    s=ref["values"]
    for j in 1:2, t in 1:4
        i=j+1
        values=[
            s["P_CHP"][i][t]+s["P_PV"][i][t]+s["P_dis"][i][t]-s["P_ch"][i][t]-s["P_HP"][i][t]-s["P_EB"][i][t]-s["P_D"][i][t],
            c.data["actors"][i]["Q_ratio"]*s["P_D"][i][t],
            s["H_src"][i][t],
            s["H_D"][i][t],
        ]
        for k in 1:4
            @constraint(op.model, op.message[4(j-1)+k, t]==values[k])
        end
    end
    r=PaperRebuild.r4_distributed_solve!(op, time()+60)
    @test r["status"]=="solved"
    @test abs(r["cost"]-r4_ledger(c, s)["actors"][1]["prepayment_cost"])<1e-4
    tr=solve_r4_distributed(c; optimizer = opt, modes, purpose = :agnb, budget_sec = 60)
    @test tr["status"]=="consensus_converged"
    @test tr["validation"]["model_pass"]
    @test maximum(abs, tr["candidate"]["values"]["P_peer"])>0.01
    central=PaperRebuild.r4_solve_stage(
        c,
        R4Spec(),
        opt,
        time()+60;
        stage = :trading,
        build_options = (; modes),
    )
    @test validate_r4_trading(c, central)["model_pass"]
    @test central["relative_gap"]<=1e-4
    @test abs(tr["candidate"]["operating_cost"]-central["solver_objective"])/max(
        1,
        abs(central["solver_objective"]),
    )<=1e-4
    for key in ("x", "z", "u")
        bad=deepcopy(sw)
        bad["trace"][1][key][1][1]+=0.01
        @test_throws ErrorException validate_r4_distributed(c, bad)
    end
    bad=deepcopy(tr)
    bad["inner_trace"][1]["q"][1][1][1]+=0.01
    @test_throws ErrorException validate_r4_distributed(c, bad)
    bad=deepcopy(sw)
    bad["agents"][1]["message"][1][1]+=0.01
    @test_throws ErrorException validate_r4_distributed(c, bad)
    bad=deepcopy(sw)
    bad["modes"][1]=0
    @test_throws ErrorException validate_r4_distributed(c, bad)
    mktempdir() do dir
        path=save_r4_distributed_run(c, sw; directory = dir, run_id = "test")
        @test read_r4_distributed_run(path).validation==sw["validation"]
        @test_throws ErrorException save_r4_distributed_run(c, sw; directory = dir, run_id = "test")
        open(joinpath(path, "result.toml"), "a") do io
            write(io, "\n# tamper\n")
        end
        @test_throws ErrorException read_r4_distributed_run(path)
    end
    limited=solve_r4_distributed(
        c;
        optimizer = opt,
        modes,
        spec = R4DistributedSpec(max_iterations = 1),
        budget_sec = 60,
    )
    @test limited["status"]=="iteration_limit"
    @test !limited["validation"]["model_pass"]
    @test haskey(limited, "candidate")
    timed=solve_r4_distributed(c; optimizer = opt, modes, budget_sec = 1e-12)
    @test timed["status"]=="time_limit"
    @test !timed["validation"]["model_pass"]
    fail=solve_r4_distributed(c; optimizer = ()->error("license missing test"), modes)
    @test fail["status"]=="license_missing"
    @test !fail["validation"]["consensus_A4_pass"]
    d=deepcopy(c.data)
    d["p2p_enabled"]=false
    nopeer=R4Case(d)
    tr0=solve_r4_distributed(nopeer; optimizer = opt, modes, purpose = :agnb, budget_sec = 60)
    @test tr0["status"]=="consensus_converged"
    @test tr0["validation"]["model_pass"]
    @test maximum(abs, tr0["candidate"]["values"]["P_peer"])<1e-8
    @test maximum(abs, tr0["candidate"]["values"]["H_peer"])<1e-8
    d=deepcopy(c.data)
    d["heat"]["pipes"][1]["U_W_mK"]*=1000
    badcase=R4Case(d)
    @test PaperRebuild.r4_loss(d["heat"]["pipes"][1])>d["heat"]["pipes"][1]["H_max"]
    infeasible=solve_r4_distributed(badcase; optimizer = opt, modes, budget_sec = 60)
    @test infeasible["status"]=="infeasible_certified"
    @test !infeasible["validation"]["model_pass"]
    @test infeasible["last_attempt_operator"]["status"]=="infeasible_certified"
end
