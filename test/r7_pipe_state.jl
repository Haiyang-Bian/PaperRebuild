using Test, PaperRebuild

@testset "R7-P1/P2 spatial state and inventory" begin
    s=r7_pipe_state([250.0, 750.0], [340.0, 300.0])
    v=r7_pipe_inventory(s; cp_J_kgK = 4200.0, reference_K = 300.0)
    @test v.mean_K≈310.0
    @test v.relative_heat_MWh≈7/600
    @test r7_pipe_temperature(s, 1000.0)==300.0
    @test r7_pipe_temperature(s, 250.0)==300.0
    @test v.mean_K!=r7_pipe_temperature(s, 1000.0)
    @test_throws ErrorException r7_pipe_state([0.0], [300.0])
    @test_throws ErrorException r7_pipe_state([1.0], [0.0])
    @test_throws ErrorException r7_pipe_temperature(s, -1.0)
    @test_throws ErrorException r7_pipe_inventory(s; cp_J_kgK = -1.0, reference_K = 300.0)
end

@testset "R7-P3/P4 exact advection and independently integrated heat loss" begin
    step(s, m, T, dt; UA = 0.0, Ta = 280.0) = r7_pipe_step(
        s;
        mass_flow_kg_s = m,
        inlet_K = T,
        ambient_K = Ta,
        dt_h = dt,
        cp_J_kgK = 4200.0,
        UA_W_K = UA,
        reference_K = 300.0,
    )
    s=r7_pipe_state([900.0], [300.0])
    a=step(s, 1.0, 330.0, 1.0)
    @test a.outlet_mean_K≈322.5
    @test a.after.mean_K≈330.0
    @test abs(a.energy_residual_MWh)<1e-12
    @test a.loss_MWh==0.0
    @test !a.normal_dispatch_verified
    reverse=step(s, -1.0, 330.0, 1.0)
    @test reverse.outlet_mean_K≈a.outlet_mean_K
    @test reverse.after.mean_K≈a.after.mean_K
    @test abs(reverse.energy_residual_MWh)<1e-12
    for amount in (0.25, 1.0, 2.5), direction in (-1, 1)
        r=step(r7_pipe_state([3600.0], [300.0]), direction*amount, 340.0, 1.0)
        @test r.outlet_mean_K≈(amount<=1 ? 300.0 : (300.0+(amount-1)*340.0)/amount)
        @test abs(r.energy_residual_MWh)<1e-12
        @test abs(r.mass_residual_kg)<1e-10
    end
    # 停流必须冷却；环境更热时符号相反。
    for Ta in (280.0, 350.0)
        r=step(s, 0.0, nothing, 0.5; UA = 100.0, Ta)
        expected=Ta+(300-Ta)*exp(-100*1800/(900*4200))
        @test r.outlet_mean_K===nothing
        @test r.after.mean_K≈expected
        @test r.loss_MWh≈900*4200*(300-expected)/3.6e9
        @test abs(r.energy_residual_MWh)<1e-12
    end
    @test_throws ErrorException step(s, 1.0, nothing, 1.0)
    @test_throws ErrorException step(s, 1.0, 300.0, 0.0)
    @test_throws ErrorException step(s, 1.0, 300.0, 1.0; UA = -1.0)
    # 相同边界下整步与两半步应满足半群性质，包括出口积分和散热积分。
    for m in (-2.0, -0.3, 0.0, 0.3, 2.0), UA in (0.0, 1e-7, 100.0), Ta in (280.0, 360.0)
        initial=r7_pipe_state([300.0, 600.0], [310.0, 335.0])
        full=step(initial, m, 325.0, 1.0; UA, Ta)
        half1=step(initial, m, 325.0, 0.5; UA, Ta)
        half2=step(half1.state, m, 325.0, 0.5; UA, Ta)
        @test full.after.mean_K≈half2.after.mean_K atol=1e-10
        @test full.output_heat_MWh≈half1.output_heat_MWh+half2.output_heat_MWh atol=1e-12
        @test full.loss_MWh≈half1.loss_MWh+half2.loss_MWh atol=1e-12
        @test abs(full.energy_residual_MWh)<1e-12
        @test all(
            isapprox(
                r7_pipe_temperature(full.state, x),
                r7_pipe_temperature(half2.state, x);
                atol = 1e-10,
            ) for x in 0.0:15.0:900.0
        )
    end
    # 反转前后保留空间状态；用独立中点积分复核非均匀指数分布的显热。
    mixed=step(step(s, 0.13, 350.0, 1.0; UA = 200.0).state, -0.07, 315.0, 1.0; UA = 50.0)
    M=mixed.after.mass_kg
    quadrature=sum(r7_pipe_temperature(mixed.state, (j-0.5)*M/100000) for j in 1:100000)/100000
    @test mixed.after.mean_K≈quadrature atol=5e-4
    @test abs(mixed.energy_residual_MWh)<1e-12
    # 与已有离散核只在无损恒流退化下比对，不强迫不同散热近似相等。
    k=fixed_flow_kernel(1.0, 1000.0, 0.01, 90.0, 1.0, 0.0)
    old=pipe_outlet([330.0], [300.0], k, 280.0)
    @test a.outlet_mean_K≈only(old)
    steady=step(s, 1.0, 330.0, 1.0; UA = 100.0)
    continued=step(steady.state, 1.0, 330.0, 1.0; UA = 100.0)
    @test continued.outlet_mean_K≈280+50*exp(-100/4200)
    @test continued.after.mean_K≈continued.before.mean_K
    @test continued.loss_MWh≈100*3600*(continued.after.mean_K-280)/3.6e9
end
