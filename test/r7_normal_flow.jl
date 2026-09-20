using Test, PaperRebuild, JuMP, HiGHS, TOML

function normal_flow_test_spec(c; fixed = false)
    h=c.data["heat"]
    T=c.data["periods"]
    pipes=reduce(vcat, permutedims(p["normal_flow_kg_s"]) for p in h["pipes"])
    src=reduce(vcat, permutedims.(h["source_flow_kg_s"]))
    load=reduce(vcat, permutedims.(h["load_flow_kg_s"]))
    r7_normal_flow_spec(
        c;
        pipe_min = fixed ? pipes : fill(2.5, size(pipes)),
        pipe_max = fixed ? pipes : fill(7.5, size(pipes)),
        source_min = fixed ? src : 0.5src,
        source_max = fixed ? src : 1.5src,
        load_min = fixed ? load : 0.5load,
        load_max = fixed ? load : 1.5load,
    )
end

@testset "R7 continuous normal flow" begin
    root=normpath(joinpath(@__DIR__, ".."))
    c=load_r7_normal_case(joinpath(root, "configs/r7/normal-hand.toml"))
    opt=optimizer_with_attributes(
        HiGHS.Optimizer,
        "threads"=>1,
        "primal_feasibility_tolerance"=>1e-9,
        "dual_feasibility_tolerance"=>1e-9,
        "mip_feasibility_tolerance"=>1e-9,
    )
    @testset "R7-F2 mass labels and independent replay" begin
        # 经过整数、非整数、跨多个入口区间与多种初始水团位置；q不是离散时延。
        for q in ([0.5, 0.5, 0.5, 0.5], [1.0, 1.0, 1.0, 1.0], [0.3, 1.7, 0.6, 2.1]),
            profile in ([0.1, 0.9], [0.9, 0.1], [0.4, 0.4])

            m=Model(opt)
            set_silent(m)
            θin=[0.2, 0.7, 0.9, 0.3]
            out=@variable(m, [1:4], lower_bound=0, upper_bound=1)
            inv=@variable(m, [1:5], lower_bound=0, upper_bound=1)
            add_r7_mass_transport!(m, q, θin, out, inv, [0.4, 0.6], profile)
            @objective(m, Min, 0)
            optimize!(m)
            @test termination_status(m)==MOI.OPTIMAL
            state=r7_pipe_state([400.0, 600.0], 300 .+ 50profile)
            for t in 1:4
                r=r7_pipe_step(
                    state;
                    mass_flow_kg_s = q[t]*1000/3600,
                    inlet_K = 300+50θin[t],
                    ambient_K = 290,
                    dt_h = 1,
                    cp_J_kgK = 4200,
                    UA_W_K = 0,
                    reference_K = 300,
                )
                @test value(out[t]) ≈ (r.outlet_mean_K-300)/50 atol=1e-9
                E=r7_pipe_inventory(r.state; cp_J_kgK = 4200, reference_K = 300).relative_heat_MWh
                @test value(inv[t+1]) ≈ E/(4200*1000*50/3.6e9) atol=1e-9
                state=r.state
            end
        end
        # 正部含真正自由变量，在跨段点两侧核对，不靠手写同一优化式充当回放。
        for x0 in (-1.0, -1e-4, 0.0, 1e-4, 1.0)
            m=Model(opt)
            set_silent(m)
            x=@variable(m, lower_bound=-2, upper_bound=2)
            y=PaperRebuild.r7_positive_part!(m, x, "test")
            @constraint(m, x==x0)
            @objective(m, Min, 0)
            optimize!(m)
            @test value(y) ≈ max(0, x0) atol=1e-9
        end
        m=Model()
        x=@variable(m)
        @test_throws Exception PaperRebuild.r7_positive_part!(m, x, "unbounded")
    end
    @testset "R7-F1 input domain and model classification" begin
        s=normal_flow_test_spec(c)
        b=build_r7_normal_flow(c, s)
        @test b.model_class=="nonconvex_MIQCP"
        @test size(b.flow["pipe"])==(1, 4)
        @test size(b.flow["source"])==(2, 4)
        @test !b.fixed_flow
        @test all(is_valid(b.model, x) for cs in values(b.constraints) for x in cs)
        @test_throws Exception build_r7_normal_flow(c, s; deadline = time()-1)
        bad=deepcopy(s)
        bad["pipe_min"]["data"][1]=0.0
        @test_throws Exception build_r7_normal_flow(c, bad)
        bad=deepcopy(s)
        bad["source_min"]["data"][1]=0.0
        @test_throws Exception build_r7_normal_flow(c, bad)
        d=deepcopy(c.data)
        d["heat"]["pipes"][1]["UA_S_W_K"]=1
        @test_throws Exception normal_flow_test_spec(R7NormalCase(d))
        d=deepcopy(c.data)
        d["thermal_model"]="node_method_fixed_v1"
        @test_throws Exception normal_flow_test_spec(R7NormalCase(d))
    end
    @testset "R7-F4 budgets frozen values and independent equations" begin
        s=normal_flow_test_spec(c; fixed = true)
        r=solve_r7_normal_flow(c, s; optimizer = opt, budget_sec = 60)
        @test r["candidate_accepted"]
        @test r["domain_cost_complete"]
        @test r["solver_objective_USD"]≈118.4 atol=1e-6
        @test r["flow_fixed"]
        @test !r["full_preplan_optimality_verified"]
        @test solve_r7_normal_flow(c, s; optimizer = opt, budget_sec = 0)["status"]=="budget_exhausted"
        @test solve_r7_normal_flow(c, s; optimizer = ()->error("license test fixture"))["status"]=="license_unavailable"
        bad=deepcopy(r)
        bad["flow_values"]["pipe"]["data"][1]+=0.1
        @test !validate_r7_normal_flow(c, s, bad)["model_pass"]
        bad=deepcopy(r)
        bad["values"]["τ_pipe_S"]["data"][1]+=0.01
        @test !validate_r7_normal_flow(c, s, bad)["model_pass"]
        bad=deepcopy(r)
        bad["case_sha256"]="bad"
        @test_throws Exception validate_r7_normal_flow(c, s, bad)
        mktempdir() do dir
            dest=joinpath(dir, "run")
            save_r7_normal_flow(c, s, r, dest)
            @test read_r7_normal_flow(dest).validation["model_pass"]
            @test_throws Exception save_r7_normal_flow(c, s, r, dest)
            open(joinpath(dest, "result.toml"), "a") do io
                write(io, "\n# changed\n")
            end
            @test_throws Exception read_r7_normal_flow(dest)
        end
    end
end
