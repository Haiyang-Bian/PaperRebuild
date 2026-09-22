using Test, PaperRebuild, Gurobi, JuMP

@testset "R7-F3 continuous flow nonconvex reference" begin
    opt=optimizer_with_attributes(
        Gurobi.Optimizer,
        "Threads"=>1,
        "NonConvex"=>2,
        "FeasibilityTol"=>1e-9,
        "OptimalityTol"=>1e-9,
        "IntFeasTol"=>1e-9,
        "MIPGap"=>1e-8,
        "DualReductions"=>0,
    )
    # 流量必须从连续区间中择取；解析最低通过质量q=.37，不在预设离散格点上。
    m=Model(opt)
    set_silent(m)
    q=@variable(m, lower_bound=0.1, upper_bound=2)
    out=@variable(m, lower_bound=0, upper_bound=1)
    inv=@variable(m, [1:2], lower_bound=0, upper_bound=1)
    add_r7_mass_transport!(m, [q], [1.0], [out], inv, [1.0], [0.0])
    @constraint(m, inv[2]>=0.37)
    @objective(m, Min, q)
    optimize!(m)
    @test termination_status(m)==MOI.OPTIMAL
    @test value(q)≈0.37 atol=1e-6
    @test value(out)≈0 atol=1e-7
    # 当同一时间步流过整管，出口必须包括本步新热水，不能强制最少一整步延迟。
    m=Model(opt)
    set_silent(m)
    q=@variable(m, lower_bound=0.1, upper_bound=3)
    out=@variable(m, lower_bound=0, upper_bound=1)
    inv=@variable(m, [1:2], lower_bound=0, upper_bound=1)
    add_r7_mass_transport!(m, [q], [1.0], [out], inv, [1.0], [0.0])
    @constraint(m, out>=0.5)
    @objective(m, Min, q)
    optimize!(m)
    @test termination_status(m)==MOI.OPTIMAL
    @test value(q)≈2 atol=1e-6
    @test value(out)≈0.5 atol=1e-6
end
