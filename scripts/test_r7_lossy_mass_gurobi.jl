using PaperRebuild, JuMP, Gurobi, Test, TOML
include(joinpath(@__DIR__, "..", "test", "r7_lossy_mass_fixtures.jl"))
length(ARGS) == 1 || error("usage: test_r7_lossy_mass_gurobi.jl NEW_OUTPUT")
destination = abspath(only(ARGS))
ispath(destination) && error("不覆盖有损核开发证据")
mkpath(destination)
opt = optimizer_with_attributes(
    Gurobi.Optimizer,
    "Threads" => 1,
    "NonConvex" => 2,
    "FeasibilityTol" => 1e-9,
    "OptimalityTol" => 1e-9,
    "IntFeasTol" => 1e-9,
    "MIPGap" => 1e-8,
    "DualReductions" => 0,
)
rows = Any[]
@testset "R7-H1/H3 nonlinear free-variable constraints" begin
    for (id, q) in
        (("integer", [1.0, 1.0]), ("zero_restart", [0.3, 0.0, 1.7]), ("switch", [0.999, 1.001]))
        started = time()
        write(
            joinpath(destination, id*"-input.toml"),
            PaperRebuild.r7_text(
                Dict(
                    "q"=>q,
                    "decay_per_h"=>0.08,
                    "budget_sec"=>60.0,
                    "kind"=>"synthetic_development",
                ),
            ),
        )
        b = lossy_kernel_fixture(q; optimizer = opt, variable_flow = true)
        set_time_limit_sec(b.model, max(0.01, 60-(time()-started)))
        optimize!(b.model)
        @test has_values(b.model)
        error = check_lossy_kernel_replay(b, q; atol = 2e-8)
        push!(
            rows,
            Dict(
                "id"=>id,
                "q"=>value.(b.flows),
                "outlet"=>value.(b.output),
                "inventory"=>value.(b.inventory),
                "maximum_normalized_replay_error"=>error,
                "status"=>string(termination_status(b.model)),
                "elapsed_sec"=>time()-started,
            ),
        )
    end
end
@testset "R7-H3 actual flow decision against analytic transport" begin
    started = time()
    target = r7_pipe_step(
        r7_pipe_state([1000.0], [310.0]);
        mass_flow_kg_s = 2000/3600,
        inlet_K = 345.0,
        ambient_K = 305.0,
        dt_h = 1,
        cp_J_kgK = 4200,
        UA_W_K = 0.1*4200*1000/3600,
        reference_K = 300,
    )
    threshold = (target.outlet_mean_K-300)/50
    write(
        joinpath(destination, "inverse-input.toml"),
        PaperRebuild.r7_text(
            Dict(
                "q_min"=>1.1,
                "q_max"=>3.0,
                "outlet_min"=>threshold,
                "decay_per_h"=>0.1,
                "kind"=>"synthetic_analytic_inverse",
                "budget_sec"=>60.0,
            ),
        ),
    )
    m = Model(opt)
    set_silent(m)
    q = @variable(m, lower_bound=1.1, upper_bound=3.0)
    out = @variable(m, [1:1], lower_bound=0, upper_bound=1)
    inventory = @variable(m, [1:2], lower_bound=0, upper_bound=1)
    block = add_r7_lossy_mass_transport!(
        m,
        [q],
        [0.9],
        out,
        inventory,
        [1.0],
        [0.2];
        dt_h = [1.0],
        decay_per_h = 0.1,
        ambient = [0.1],
    )
    @constraint(m, out[1]>=threshold)
    @objective(m, Min, q)
    set_time_limit_sec(m, max(0.01, 60-(time()-started)))
    optimize!(m)
    @test has_values(m)
    @test value(q) ≈ 2.0 atol=1e-5
    @test abs(objective_value(m)-objective_bound(m)) < 1e-5
    replay=r7_pipe_step(
        r7_pipe_state([1000.0], [310.0]);
        mass_flow_kg_s = value(q)*1000/3600,
        inlet_K = 345.0,
        ambient_K = 305.0,
        dt_h = 1,
        cp_J_kgK = 4200,
        UA_W_K = 0.1*4200*1000/3600,
        reference_K = 300,
    )
    @test abs(value(out[1])-(replay.outlet_mean_K-300)/50)<1e-7
    push!(
        rows,
        Dict(
            "id"=>"inverse",
            "q"=>value(q),
            "outlet"=>value(out[1]),
            "objective"=>objective_value(m),
            "bound"=>objective_bound(m),
            "status"=>string(termination_status(m)),
            "elapsed_sec"=>time()-started,
        ),
    )
end
write(joinpath(destination, "results.toml"), PaperRebuild.r7_text(Dict("records"=>rows)))
