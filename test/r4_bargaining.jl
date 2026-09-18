using Test, JuMP, Clarabel, TOML

@testset "R4 Nash allocation and participation" begin
    # 手算：合计9单位剩余，按1:2:3分配，转移支付之和为零。
    u=[-3.0, 8.0, 5.0]
    d=[-5.0, 2.0, 4.0]
    w=[1.0, 2.0, 3.0]
    r=r4_nash_allocation(u, d, w)
    @test r["gain"]≈[1.5, 3.0, 4.5]
    @test r["total_transfer"]≈[-0.5, -3.0, 3.5]
    @test validate_r4_allocation(r)["strict_improvement"]
    @test r4_nash_allocation(u, d, w .* 100)["gain"]≈r["gain"]
    @test r4_nash_allocation(u .* 100, d .* 100, w)["gain"]≈100 .* r["gain"]
    # 改动旧结算不会改变总可分剩余，净增量转移恰好抵消这一变化。
    cash=[2.0, -3.0, 1.0]
    shifted=r4_nash_allocation(u .+ cash, d, w)
    @test shifted["utility_after"]≈r["utility_after"]
    @test shifted["total_transfer"]≈r["total_transfer"] .- cash
    for bad in ([0.0, 1, 1], [-1.0, 2, 3], [NaN, 2, 3], [Inf, 2, 3], [1.0, 2])
        @test_throws ErrorException r4_nash_allocation(u, d, bad)
    end
    @test_throws ErrorException r4_nash_allocation([1.0], [0.0], [1.0])
    zero=r4_nash_allocation([1.0, 3.0], [2.0, 2.0], [1.0, 1.0])
    @test zero["status"]=="zero_surplus_degenerate"
    @test validate_r4_allocation(zero)["allocation_pass"]
    @test !validate_r4_allocation(zero)["strict_improvement"]
    for amount in (1.0, 1e-12)
        negative=r4_nash_allocation([-amount, 0.0], [0.0, 0.0], [1.0, 1.0])
        @test negative["status"]=="negative_surplus"
        @test !haskey(negative, "total_transfer")
        @test validate_r4_allocation(negative)["record_pass"]
        @test !validate_r4_allocation(negative)["allocation_pass"]
    end
    changed=deepcopy(r)
    changed["total_transfer"][1]+=0.1
    @test !validate_r4_allocation(changed)["allocation_pass"]
    changed=deepcopy(r)
    changed["gain"][1]+=0.1
    @test !validate_r4_allocation(changed)["record_pass"]
    changed=deepcopy(r)
    changed["weights"][1]+=1.0
    @test !validate_r4_allocation(changed)["record_pass"]
    mktempdir() do dir
        file=joinpath(dir, "allocation.toml")
        write(file, PaperRebuild.r4_text(r))
        @test validate_r4_allocation(TOML.parsefile(file))==validate_r4_allocation(r)
    end
    # 独立指数锥求解log增益问题，而非再算同一解析式。
    m=Model(
        optimizer_with_attributes(
            Clarabel.Optimizer,
            "tol_gap_abs"=>1e-10,
            "tol_gap_rel"=>1e-10,
            "tol_feas"=>1e-10,
        ),
    )
    set_silent(m)
    set_time_limit_sec(m, 60.0)
    @variable(m, p[1:3])
    @variable(m, z[1:3])
    @constraint(m, sum(p)==0)
    @constraint(m, [i=1:3], [z[i], 1.0, u[i]+p[i]-d[i]] in MOI.ExponentialCone())
    @objective(m, Max, sum(w[i]/sum(w)*z[i] for i in 1:3))
    optimize!(m)
    @test termination_status(m)==MOI.OPTIMAL
    @test maximum(abs.(value.(p) .- r["total_transfer"]))<=1e-4
    @test abs(objective_value(m)-r["log_nash"])<=1e-4
    @test abs(objective_value(m)-dual_objective_value(m))<=1e-4
    root=normpath(joinpath(@__DIR__, ".."))
    c=load_r4_case(joinpath(root, "configs", "r4", "baseline", "import_flexible.toml"))
    wc=r4_bargaining_weights(c)
    @test wc["weights"]≈[1.82, 1.02, 0.8]
    @test wc["weights"][1]≈sum(wc["weights"][2:3])
    @test r4_bargaining_weights(c; rule = :equal_v1)["weights"]==ones(3)
    @test_throws ErrorException r4_bargaining_weights(c; rule = :guessed)
    # 可选本地集成：保存数值重新验证，绝不只信stored pass。
    parents=joinpath(root, "results", "runs", "r4", "r4-baseline-20260918")
    if isdir(parents)
        ag=read_r4_run(joinpath(parents, "import_flexible--independent_exact")).result
        sw=read_r4_run(joinpath(parents, "import_flexible--central_exact")).result
        before=deepcopy(sw)
        out=r4_allocate_coordination(c, ag, sw; weights = wc["weights"])
        @test out["validation"]["strict_improvement"]
        @test sum(out["incremental_compensation"])≈0 atol=1e-6
        @test out["previous_utility"] .+ out["incremental_compensation"]≈out["allocation"]["utility_after"]
        @test sw==before
        missing=deepcopy(ag)
        delete!(missing, "values")
        @test_throws ErrorException r4_allocate_coordination(
            c,
            missing,
            sw;
            weights = wc["weights"],
        )
        cc=load_r4_case(joinpath(root, "configs", "r4", "baseline", "open_flexible.toml"))
        @test_throws ErrorException r4_allocate_coordination(cc, ag, sw; weights = wc["weights"])
    end
end
