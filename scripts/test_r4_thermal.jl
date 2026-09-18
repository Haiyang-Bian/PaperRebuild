include(joinpath(@__DIR__, "..", "test", "r4_thermal.jl"))
if "--gurobi" in ARGS
    include("r4_setup.jl")
    optimizer=r4_optimizer(:gurobi)
    @testset "R4-T2 variable flow Gurobi handcase" begin
        for idle in (false, true), loss in (:reference, :exponential)
            c, options=r4_thermal_handcase(; idle)
            # 运行方向和设备数据固定，流量及温度自由；不注入参考解。
            r=Base.invokelatest(
                solve_r4_thermal,
                c;
                optimizer,
                spec = R4ThermalSpec(; policy = :fixed, electric = :exact, loss),
                modes = options.modes,
                electric_schedule = options.electric_schedule,
                heat_open = options.heat_open,
                heat_active = Int.(options.mass_schedule["m_pipe"] .> 0),
                budget_sec = 60.0,
            )
            println((;
                idle,
                loss,
                status = r["status"],
                model = r["validation"]["model_pass"],
                failed = [x for x in r["validation"]["rows"] if !x["pass"]],
            ))
            for log in r["solves"]
                haskey(log, "error_summary") && println(log["error_summary"])
            end
            @test r["validation"]["model_pass"]
            @test r["validation"]["electric_original_pass"]
        end
    end
end
