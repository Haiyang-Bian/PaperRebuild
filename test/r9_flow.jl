using Test, TOML, JuMP

# 用已保存的CF原物理候选作包含关系见证；不优化，不把参考值注入PG。
function r9_test_flow_embedding(c, b, saved)
    point = Dict{VariableRef,Float64}()
    for (key, array) in b.variables
        startswith(key, "alpha_") ||
            startswith(key, "beta_") ||
            key == "r9_inverse_relative" ||
            haskey(saved, key) ||
            error("缺少见证变量$key")
        (startswith(key, "alpha_") || startswith(key, "beta_")) && continue
        vals =
            key == "r9_inverse_relative" ?
            [
                first(c.data["heat"]["pipes"][p]["fixed_flow"])/saved["m_pipe"][p][t] for
                p in axes(array, 1), t in axes(array, 2)
            ] : ndims(array) == 1 ? saved[key] : permutedims(hcat(saved[key]...))
        for i in eachindex(array)
            array[i] isa VariableRef && (point[array[i]] = vals[i])
        end
    end
    for _ in 1:3
        before = length(point)
        for cr in all_constraints(b.model, AffExpr, MOI.EqualTo{Float64})
            obj = constraint_object(cr)
            unknown = [(a, x) for (a, x) in linear_terms(obj.func) if !haskey(point, x) && a != 0]
            length(unknown) == 1 || continue
            a, x = only(unknown)
            known =
                constant(obj.func) +
                sum(k*point[y] for (k, y) in linear_terms(obj.func) if haskey(point, y); init = 0.0)
            point[x] = (obj.set.value-known)/a
        end
        length(point) == before && break
    end
    @test Set(keys(point)) == Set(all_variables(b.model))
    return (; point, violations = primal_feasibility_report(b.model, point; atol = 0.0))
end

@testset "R9-V1:V4 full flow box, derivatives and terminal memory" begin
    root = normpath(joinpath(@__DIR__, ".."))
    parent = joinpath(root, "results/summaries/r9-numerics-20260921-v2")
    c = load_r9_pv_case(joinpath(parent, "case.toml"))
    domain = audit_r9_flow_domain(c)
    @test domain.pass
    @test length(domain.rows) == 37
    @test maximum(x.mass_coverage_ratio for x in domain.rows) ≈ 1/3.6
    @test all(x -> x.mass_coverage_ratio < 1, domain.rows)
    for (p, pipe) in enumerate(c.data["heat"]["pipes"])
        mass, dt = domain.rows[p].mass_kg, domain.rows[p].dt_s
        m0 = first(pipe["fixed_flow"])
        rate =
            pipe["epsilon_W_mK"] /
            (c.data["heat"]["rho_kg_m3"] * c.data["heat"]["cp_J_kgK"] * pipe["area_m2"])
        for a in (0.6, 0.81, 1.0, 1.4), b in (0.6, 1.13, 1.4)
            flows = m0 .* [a, b]
            closed = r9_transport_coefficients(flows..., mass, dt; loss_rate = rate)
            general = r3_transport_jacobian(flows, mass, dt; loss_rate = rate)
            @test !general.switching
            @test closed.alpha ≈ general.α
            @test closed.beta ≈ general.β
            @test closed.weights ≈ general.w
            @test closed.Jweights ≈ general.Jw atol=1e-12
            @test closed.residence_s ≈ general.residence
            @test closed.Jresidence ≈ general.Jr
            @test closed.attenuation ≈ general.decay
            @test closed.Jattenuation ≈ general.Jdecay
            @test closed.Jattenuation[2] > 0
        end
        flows = m0 .* [0.81, 1.13]
        closed = r9_transport_coefficients(flows..., mass, dt; loss_rate = rate)
        # 沿共同缩放方向保持管道流量为正；网络级灵敏度尚未据此宣称通过。
        direction = m0 .* [0.2, -0.1]
        for step in (1e-3, 1e-4, 1e-5)
            plus = r9_transport_coefficients(
                (flows .+ step .* direction)...,
                mass,
                dt;
                loss_rate = rate,
            )
            minus = r9_transport_coefficients(
                (flows .- step .* direction)...,
                mass,
                dt;
                loss_rate = rate,
            )
            @test maximum(abs, (plus.weights-minus.weights)/(2step) - closed.Jweights*direction) <
                  1e-3
            @test abs(
                (plus.attenuation-minus.attenuation)/(2step) -
                sum(closed.Jattenuation .* direction),
            ) < 1e-3
        end
        @test r9_transport_coefficients(flows..., mass, dt).attenuation == 1.0
        scaled = r9_transport_coefficients((flows .* 1000)..., mass*1000, dt; loss_rate = rate)
        @test scaled.weights ≈ closed.weights
        @test scaled.attenuation ≈ closed.attenuation
        @test scaled.Jattenuation .* 1000 ≈ closed.Jattenuation
    end
    @test_throws ArgumentError r9_transport_coefficients(1, 1, 3600, 3600)
    @test_throws ArgumentError r9_transport_coefficients(0, 1, 600, 3600)
    @test_throws ArgumentError r9_transport_coefficients(1, 1, 600, 3600; loss_rate = -1)
    @test_throws ArgumentError r9_transport_coefficients(NaN, 1, 600, 3600)
    bad = deepcopy(c.data)
    bad["heat"]["pipes"][1]["flow_min"] = domain.rows[1].mass_kg / domain.rows[1].dt_s
    @test !audit_r9_flow_domain(R2Case(bad, c.sha256)).pass
    bad["heat"]["pipes"][1]["flow_history"] = Float64[]
    @test_throws ArgumentError audit_r9_flow_domain(R2Case(bad, c.sha256))

    saved = TOML.parsefile(joinpath(parent, "runs/cf_ct_gurobi_original/result.toml"))["stage"]
    @test all(x.pass for x in r9_flow_terminal_rows(c, saved))
    @test length(r9_flow_terminal_rows(c, saved)) == 3*37
    @test isempty(r9_flow_terminal_rows(c, Dict()))
    changed = deepcopy(saved)
    changed["values"]["m_pipe"][1][end] *= 1.1
    @test all(x.pass for x in PaperRebuild.r9_terminal_rows(c, changed))
    @test !all(x.pass for x in r9_flow_terminal_rows(c, changed))
    # 相同末温，改变末流量后，下一时段同一控制的出口温度仍改变。
    altered = deepcopy(c.data)
    altered["heat"]["pipes"][1]["flow_history"][end] *= 1.1
    v = saved["values"]
    original_out = PaperRebuild.r3_mass_replay(c, v, 1, 1, "S").out
    altered_out = PaperRebuild.r3_mass_replay(R2Case(altered, c.sha256), v, 1, 1, "S").out
    @test abs(original_out-altered_out) > 1e-4
    for mode in (:CF_CT, :CF_VT, :VF_CT, :VF_VT)
        b = build_r9_flow_model(c; mode)
        @test b.class == (mode in (:CF_CT, :CF_VT) ? "SOCP" : "nonconvex")
        @test !has_values(b.model)
        @test b.operation.mode == mode
        @test b.terminal_interpretation == "literal"
        @test length(b.constraints["R9-V4-flow-memory"]) == 37
        @test length(b.constraints["R9-V4-temperature-memory"]) == 74
        @test all(!haskey(b.constraints, id) for id in ("3-27", "3-28", "3-30", "3-31"))
        if mode in (:VF_CT, :VF_VT)
            @test !b.fixed_flows
            @test length(b.constraints["R9-V1-reciprocal"]) == 37*24
            @test all(!is_fixed(x) for x in b.variables["m_pipe"])
        end
        witness = r9_test_flow_embedding(c, b, saved["values"])
        @test maximum(values(witness.violations); init = 0.0) <= 1e-6
        if mode == :VF_VT
            # 只检验输运组件：任意盒内管流不被冒称满足全网端口/混合或调度关系。
            changed_values = deepcopy(saved["values"])
            point = copy(witness.point)
            for (p, pipe) in enumerate(c.data["heat"]["pipes"]), t in 1:c.data["T"]
                m0 = first(pipe["fixed_flow"])
                flow = m0*(1 + 0.25sin(p+t))
                changed_values["m_pipe"][p][t] = flow
                point[b.variables["m_pipe"][p, t]] = flow
                point[b.variables["r9_inverse_relative"][p, t]] = m0/flow
            end
            for p in eachindex(c.data["heat"]["pipes"]), t in 1:c.data["T"], side in ("S", "R")
                replay = PaperRebuild.r3_mass_replay(c, changed_values, p, t, side)
                point[b.variables["tau_"*side*"_star"][p, t]] = replay.star
                point[b.variables["tau_"*side*"_out"][p, t]] = replay.out
            end
            for id in ("R9-V1-reciprocal", "R9-V2-star", "R9-V3-loss")
                residual = maximum(
                    abs(
                        value(x -> point[x], constraint_object(cr).func) -
                        constraint_object(cr).set.value,
                    ) for cr in b.constraints[id]
                )
                @test residual < 1e-9
            end
        end
    end
    physical = build_r9_flow_model(c; mode = :VF_VT, physical = true)
    physical_witness = r9_test_flow_embedding(c, physical, saved["values"])
    @test maximum(values(physical_witness.violations); init = 0.0) <= 1e-6
    @test haskey(physical.constraints, "R3-electric-equality")
    fixed = build_r9_flow_model(c; mode = :VF_VT, flow_schedule = v["m_pipe"])
    @test fixed.class == "SOCP" && fixed.fixed_flows
    @test_throws ArgumentError build_r9_flow_model(c; mode = :unknown)
end
