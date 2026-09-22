# R9-RI2/RI3：实际流量变量的指数初态核；目标/界和独立水团回放分别验收。
using PaperRebuild, JuMP, Gurobi, Test, TOML
const PR=PaperRebuild
length(ARGS)==1 || error("usage: test_r7_initial_profile_gurobi.jl NEW_OUTPUT")
destination=abspath(only(ARGS))
ispath(destination) && error("不覆盖初态核开发证据")
mkpath(destination)
opt=optimizer_with_attributes(
    Gurobi.Optimizer,
    "OutputFlag"=>0,
    "Threads"=>1,
    "NonConvex"=>2,
    "FeasibilityTol"=>1e-9,
    "OptimalityTol"=>1e-9,
    "IntFeasTol"=>1e-9,
    "MIPGap"=>1e-8,
)
rows=Any[]
@testset "R9-RI2 variable transport with inherited exponent profiles" begin
    for (id, targets, rate) in
        (("lossless_stop", [0.2, 0.0, 0.9], 0.0), ("lossy_switch", [0.39, 0.62], 0.08))
        started=time()
        state=PR.R7PipeState([
            PR.R7PipeSegment(400.0, 290.0, 45.0, 0.12/1000, true),
            PR.R7PipeSegment(600.0, 340.0, -15.0, 0.07/1000, false),
        ])
        initial=PR.r7_initial_transport(
            r7_initial_profile(state; provenance = "synthetic nonlinear kernel"),
            1000.0,
            300.0,
            350.0,
        )
        n=length(targets)
        write(
            joinpath(destination, id*"-input.toml"),
            PR.r7_text(
                Dict(
                    "origin"=>"synthetic_development",
                    "q"=>targets,
                    "rate_per_h"=>rate,
                    "dt_h"=>1.0,
                    "budget_sec"=>60.0,
                    "initial_profile"=>r7_initial_profile(
                        state;
                        provenance = "synthetic nonlinear kernel",
                    ),
                ),
            ),
        )
        model=Model(opt)
        q=@variable(model, [1:n], lower_bound=0.0, upper_bound=2.0)
        out=@variable(model, [1:n], lower_bound=0.0, upper_bound=1.0)
        inventory=@variable(model, [1:(n+1)], lower_bound=0.0, upper_bound=1.0)
        for t in 1:n
            @constraint(model, q[t]==targets[t])
        end
        block=add_r7_lossy_mass_transport!(
            model,
            q,
            fill(0.8, n),
            out,
            inventory,
            initial.mass,
            initial.mean;
            initial_spatial = initial.spatial,
            dt_h = ones(n),
            decay_per_h = rate,
            ambient = fill(-0.2, n),
            deadline = started+60,
        )
        @objective(model, Min, 0)
        set_time_limit_sec(model, max(0.01, 60-(time()-started)))
        optimize!(model)
        @test has_values(model)
        current=state
        errors=Float64[]
        for t in 1:n
            step=r7_pipe_step(
                current;
                mass_flow_kg_s = value(q[t])*1000/3600,
                inlet_K = 340.0,
                ambient_K = 290.0,
                dt_h = 1.0,
                cp_J_kgK = 4200,
                UA_W_K = rate*4200*1000/3600,
                reference_K = 300.0,
            )
            if targets[t]>0
                e=abs(300+50value(out[t])-step.outlet_mean_K)
                push!(errors, e)
                @test e<=1e-6
            end
            @test value(inventory[t+1])≈step.after.relative_heat_MWh/(4200*1000*50/3.6e9) atol=2e-8
            @test value(block.loss[t])≈step.loss_MWh/(4200*1000*50/3.6e9) atol=2e-8
            current=step.state
        end
        push!(
            rows,
            Dict(
                "id"=>id,
                "status"=>string(termination_status(model)),
                "q"=>value.(q),
                "outlet"=>value.(out),
                "inventory"=>value.(inventory),
                "maximum_outlet_error_K"=>maximum(errors),
                "elapsed_sec"=>time()-started,
            ),
        )
    end
end
@testset "R9-RI2 flow decision against analytic exponential initial mean" begin
    started=time()
    # 无时间散热、整管已排出(q>1)：T_out=T_in-(T_in-T_initial_mean)/q，严格递增。
    state=PR.R7PipeState([PR.R7PipeSegment(1000.0, 300.0, 10.0, 0.3/1000, true)])
    initial=PR.r7_initial_transport(
        r7_initial_profile(state; provenance = "analytic inverse"),
        1000.0,
        300.0,
        350.0,
    )
    mean_K=300+10*(-expm1(-0.3))/0.3
    threshold=(345-(345-mean_K)/2-300)/50
    write(
        joinpath(destination, "inverse-input.toml"),
        PR.r7_text(
            Dict(
                "origin"=>"synthetic_analytic_inverse",
                "initial_mean_K"=>mean_K,
                "target_outlet_K"=>300+50threshold,
                "expected_q"=>2.0,
                "budget_sec"=>60.0,
            ),
        ),
    )
    model=Model(opt)
    q=@variable(model, lower_bound=1.1, upper_bound=3.0)
    out=@variable(model, [1:1], lower_bound=0.0, upper_bound=1.0)
    inventory=@variable(model, [1:2], lower_bound=0.0, upper_bound=1.0)
    add_r7_mass_transport!(
        model,
        [q],
        [0.9],
        out,
        inventory,
        initial.mass,
        initial.mean;
        initial_spatial = initial.spatial,
        deadline = started+60,
    )
    @constraint(model, out[1]>=threshold)
    @objective(model, Min, q)
    set_time_limit_sec(model, max(0.01, 60-(time()-started)))
    optimize!(model)
    @test has_values(model)
    @test value(q)≈2.0 atol=1e-5
    @test abs(objective_value(model)-objective_bound(model))<=1e-5
    replay=r7_pipe_step(
        state;
        mass_flow_kg_s = value(q)*1000/3600,
        inlet_K = 345.0,
        ambient_K = 300.0,
        dt_h = 1.0,
        cp_J_kgK = 4200,
        UA_W_K = 0.0,
        reference_K = 300.0,
    )
    @test 300+50value(out[1])≈replay.outlet_mean_K atol=1e-6
    push!(
        rows,
        Dict(
            "id"=>"inverse",
            "status"=>string(termination_status(model)),
            "q"=>value(q),
            "objective"=>objective_value(model),
            "bound"=>objective_bound(model),
            "elapsed_sec"=>time()-started,
        ),
    )
end
write(joinpath(destination, "results.toml"), PR.r7_text(Dict("records"=>rows)))
