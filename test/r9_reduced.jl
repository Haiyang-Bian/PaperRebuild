# 直接赋值源温后，用独立质量回放和旧验证器核对前向热块；不以重复实现替代验收。
@testset "R9-N1:N4 forward thermal substitution and bounded arithmetic" begin
    root = normpath(joinpath(@__DIR__, ".."))
    c = load_r9_pv_case(joinpath(root, "results/summaries/r9-pv-batch-20260920-v4/case.toml"))
    for mode in (:CF_CT, :CF_VT)
        b = build_r9_reduced_model(c; mode)
        @test b.class == "SOCP"
        @test !has_values(b.model)
        @test all(x.pass for x in b.constant_checks)
        point = Dict(x => 0.0 for x in all_variables(b.model))
        if mode == :CF_VT
            for (j, node) in enumerate(c.data["heat"]["nodes"]), t in 1:c.data["T"]
                node["role"] == "source" || continue
                expression = b.variables["tau_S_port"][j, t]
                a, x = only(collect(linear_terms(expression)))
                point[x] = (c.data["heat"]["S_reference_K"] + 0.2sin(j+t) - constant(expression))/a
            end
        end
        eval_array(array) = begin
            vals = [value(x -> point[x], x) for x in array]
            ndims(vals) == 1 ? collect(vals) : [collect(row) for row in eachrow(vals)]
        end
        values = Dict(k => eval_array(array) for (k, array) in b.variables)
        for (j, node) in enumerate(c.data["heat"]["nodes"]), t in 1:c.data["T"]
            node["role"] == "source" || continue
            g = findfirst(g -> g["heat_node"] == j, c.data["devices"])
            values["H_device"][g][t] = values["H_port"][j][t]
            values["P_device"][g][t] = values["H_port"][j][t]/c.data["devices"][g]["heat_ratio"]
        end
        stage = PaperRebuild.r3_solve(c, () -> b, nothing)
        stage["values"] = values
        stage["objective"] = PaperRebuild.r3_operating_cost(c, values)
        stage["operating_cost"] = stage["objective"]
        stage["solver_objective"] = stage["objective"]
        checked = validate_r3_solution(c, stage)
        # 此处未调度电网，电根边界同样不属于热块恒等式测试。
        excluded = Set((
            "3-2",
            "3-3:8",
            "3-9",
            "3-10",
            "3-11",
            "3-12",
            "3-13",
            "3-14",
            "R2-root-voltage",
            "pre-SOC-electric",
        ))
        thermal = [row for row in checked.rows if row.equation ∉ excluded]
        @test length(thermal) > 10000
        @test isempty([
            (row.equation, row.entity, row.t, row.residual, row.unit) for
            row in thermal if !row.pass
        ])
        for side in ("S", "R")
            errors = [
                abs(
                    PaperRebuild.r3_mass_replay(c, values, p, t, side).out -
                    values["tau_"*side*"_out"][p][t],
                ) for p in eachindex(c.data["heat"]["pipes"]), t in 1:c.data["T"]
            ]
            @test maximum(errors) < 1e-9
        end
        @test r9_daily_heat_balance(c, values).pass
        @test r9_daily_heat_balance(c, values).residual_MWh < 1e-9
        terminal = PaperRebuild.r9_terminal_rows(c, stage)
        @test all(row.pass for row in terminal) == (mode == :CF_CT)
    end
    model = Model()
    refs, checks = Dict{String,Vector{Any}}(), NamedTuple[]
    @test_throws ArgumentError PaperRebuild.r9_reduced_row!(
        model,
        refs,
        checks,
        "test",
        1e-5,
        :eq,
        0.0,
    )
    @test_throws ArgumentError build_r9_reduced_model(c; mode = :VF_VT)
    @test_throws ArgumentError solve_r9_reduced_case(c; budget_sec = 601)
    stopped = solve_r9_reduced_case(c; budget_sec = 0)
    @test stopped["status"] == "time_limit_no_solution"
    @test !stopped["validation"]["model_pass"]
    @test !haskey(stopped, "diagnostic_candidate")
    @testset "R9-N6 exact full nullspace" begin
        rank_one = PaperRebuild.r9_exact_nullspace([1.0 1.0; 2.0 2.0])
        @test rank_one.rank == 1
        @test size(rank_one.U) == (2, 1)
        @test maximum(abs, [1.0 1.0; 2.0 2.0]*rank_one.U) < 1e-14
        @test PaperRebuild.r9_exact_nullspace([1.0 1.0; 1.0 nextfloat(1.0)]).rank == 2
        @test PaperRebuild.r9_exact_nullspace(zeros(0, 0)).rank == 0
        anchored = build_r9_reduced_model(c; mode = :CF_VT, terminal = :reference_anchored)
        cert = anchored.terminal_certificate
        @test cert["rank_exact_binary"] == 32
        @test cert["free_source_count"] == 16
        @test cert["basis_gram_error"] < 1e-10
        @test cert["basis_error_bound_K"] < 1e-10
        @test maximum(abs, cert["anchor_shifts_K"]) < 1e-10
        @test length(anchored.variables["r9_terminal_coordinates"]) == 16
        @test !haskey(anchored.constraints, "R9-P6")
        @test length(anchored.constraints["R9-N6-source-bound"]) == 96
        @test_throws ArgumentError build_r9_reduced_model(c; terminal = :unknown)
    end
end
