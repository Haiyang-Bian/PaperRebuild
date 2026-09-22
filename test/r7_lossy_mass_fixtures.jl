function lossy_kernel_fixture(
    q;
    optimizer = nothing,
    rate = 0.08,
    dt = ones(length(q)),
    ambient = fill(-0.2, length(q)),
    initial = [0.6, 0.8],
    inlet = fill(0.7, length(q)),
    order = 10,
    variable_flow = false,
)
    m = optimizer === nothing ? Model() : Model(optimizer)
    set_silent(m)
    T = length(q)
    if variable_flow
        flows = [
            @variable(m, lower_bound = 0, upper_bound = max(2.5, 1.2x), base_name = "q_$t") for
            (t, x) in enumerate(q)
        ]
        for t in 1:T
            @constraint(m, flows[t] == q[t])
        end
    else
        flows = q
    end
    output = @variable(m, [1:T], lower_bound = 0, upper_bound = 1)
    inventory = @variable(m, [1:(T+1)], lower_bound = 0, upper_bound = 1)
    block = add_r7_lossy_mass_transport!(
        m,
        flows,
        inlet,
        output,
        inventory,
        [0.4, 0.6],
        initial;
        dt_h = dt,
        decay_per_h = rate,
        ambient,
        order,
    )
    @objective(m, Min, 0)
    (; model = m, output, inventory, block, flows)
end

function check_lossy_kernel_replay(
    b,
    q;
    rate = 0.08,
    dt = ones(length(q)),
    ambient = fill(-0.2, length(q)),
    initial = [0.6, 0.8],
    inlet = fill(0.7, length(q)),
    atol = 1e-8,
)
    state = r7_pipe_state([400.0, 600.0], 300 .+ 50initial)
    scale = 4200*1000*50/3.6e9
    errors = Float64[]
    for t in eachindex(q)
        step = r7_pipe_step(
            state;
            mass_flow_kg_s = q[t]*1000/(3600dt[t]),
            inlet_K = 300+50inlet[t],
            ambient_K = 300+50ambient[t],
            dt_h = dt[t],
            cp_J_kgK = 4200,
            UA_W_K = rate*4200*1000/3600,
            reference_K = 300,
        )
        if q[t] > 0
            error = abs(value(b.output[t])-(step.outlet_mean_K-300)/50)
            @test error <= atol
            push!(errors, error)
        end
        error = abs(value(b.inventory[t+1])-step.after.relative_heat_MWh/scale)
        @test error <= atol
        push!(errors, error)
        @test value(b.block.loss[t]) ≈ step.loss_MWh/scale atol=atol
        @test abs(step.energy_residual_MWh) < 1e-12
        state = step.state
    end
    maximum(errors)
end
