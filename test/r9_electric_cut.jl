using Test, PaperRebuild, TOML, JuMP, HiGHS

function cut_fixture()
    c = load_r7_recovery_case(joinpath(dirname(@__DIR__), "configs/r7/recovery-hand.toml"))
    d = deepcopy(c.data)
    d["electric"]["lines"][1]["P_max_MW"] = 0.1
    c = R7RecoveryCase(d)
    with_r7_critical_load(c, [[0.0], [0.6]]; provenance = "synthetic network-cut hand example")
end

# 独立构造完整的乐观有功运输LP；不调用割计算，也不预先使用选定区域。
function cut_transport_lp(c, fault, t, w)
    d, e = c.data, c.data["electric"]
    m = Model(HiGHS.Optimizer)
    set_silent(m)
    set_optimizer_attribute(m, "threads", 1)
    N, L, G = e["nodes"], length(e["lines"]), length(d["devices"])
    @variable(m, f[1:L])
    @variable(m, p[1:G] >= 0)
    @variable(m, served[1:N] >= 0)
    for (l, x) in enumerate(e["lines"])
        set_lower_bound(f[l], -x["P_max_MW"] * (1 - fault[l]))
        set_upper_bound(f[l], x["P_max_MW"] * (1 - fault[l]))
    end
    for (g, x) in enumerate(d["devices"])
        upper =
            x["kind"] == "EB" ? 0.0 :
            x["kind"] == "PV" ? d["renewable_factor"] * x["available_MW"][t][w] : x["P_max_MW"]
        set_upper_bound(p[g], upper)
    end
    for n in 1:N
        set_upper_bound(served[n], d["load_service"]["critical_load_MW"][n][t])
        @constraint(
            m,
            sum(p[g] for g in 1:G if d["devices"][g]["electric_node"] == n) +
            sum(f[l] for l in 1:L if e["lines"][l]["to"] == n) ==
            served[n] + sum(f[l] for l in 1:L if e["lines"][l]["from"] == n)
        )
    end
    @objective(m, Max, sum(served))
    optimize!(m)
    @test termination_status(m) == JuMP.MOI.OPTIMAL
    sum(row[t] for row in d["load_service"]["critical_load_MW"]) - objective_value(m)
end

@testset "R9-EC1 and R9-EC2 regional necessary energy bound" begin
    c = cut_fixture()
    original = deepcopy(c.data)
    healthy = r9_electric_cut_bound(c, [0], [2])
    failed = r9_electric_cut_bound(c, [1], [2])
    @test healthy["loss_lower_MWh"] ≈ 0.3 atol=1e-14
    @test failed["loss_lower_MWh"] ≈ 0.4 atol=1e-14
    @test healthy["boundary_lines"] == [1] && isempty(failed["boundary_lines"])
    @test healthy["internal_generator_ids"] == ["BES2"]
    @test !healthy["recovery_feasibility_certified"] && !healthy["original_minimum_loss_certified"]
    @test !healthy["optimization_performed"]
    @test isequal(c.data, original)
    @test validate_r9_electric_cut_bound(c, healthy)["certificate_pass"]
    for fault in ([0], [1])
        lower = r9_electric_cut_bound(c, fault, [2])["loss_lower_MWh"]
        @test lower ≈ cut_transport_lp(c, fault, 1, 1) atol=1e-8
    end
    @test r9_electric_cut_bound(c, [0], Int[])["loss_lower_MWh"] == 0
    @test r9_electric_cut_bound(c, [0], [1, 2])["loss_lower_MWh"] == 0
    @test r9_electric_cut_bound(c, [0], [2, 1]) == r9_electric_cut_bound(c, [0], [1, 2])
    for nodes in ([2, 2], [0], [3], [true])
        @test_throws ErrorException r9_electric_cut_bound(c, [0], nodes)
    end
    for fault in ([2], [0, 0], [true], [0.0])
        @test_throws ErrorException r9_electric_cut_bound(c, fault, [2])
    end
    @test_throws ErrorException r9_electric_cut_bound(c, [0], [2]; deadline = time()-1)
    @test_throws ErrorException r9_electric_cut_bound(c, [0], [2]; deadline = NaN)
    bad = deepcopy(healthy)
    bad["threshold_excluded"] = true
    @test_throws ErrorException validate_r9_electric_cut_bound(c, bad)
    bad = deepcopy(healthy)
    bad["rows"][1]["boundary_import_upper_MW"] = 0.0
    @test_throws ErrorException validate_r9_electric_cut_bound(c, bad)
    mktempdir() do dir
        p = joinpath(dir, "certificate.toml")
        open(io -> TOML.print(io, healthy; sorted = true), p, "w")
        @test validate_r9_electric_cut_bound(c, TOML.parsefile(p))["certificate_pass"]
    end
    d = deepcopy(c.data)
    d["dt_h"] = 0.5
    @test r9_electric_cut_bound(R7RecoveryCase(d), [0], [2])["loss_lower_MWh"] ≈ 0.15 atol=1e-14
    d = deepcopy(c.data)
    d["devices"][2]["initial_MWh"] = [0.0]
    @test r9_electric_cut_bound(R7RecoveryCase(d), [0], [2])["loss_lower_MWh"] ==
          healthy["loss_lower_MWh"]
    d["devices"][1]["commitment"] = [0]
    @test r9_electric_cut_bound(R7RecoveryCase(d), [0], [1, 2])["loss_lower_MWh"] == 0
    d = deepcopy(c.data)
    d["loss_limit_MWh"] = 0.1
    @test r9_electric_cut_bound(R7RecoveryCase(d), [0], [2])["threshold_excluded"]
    d["loss_limit_MWh"] = 0.3 - 1e-8
    close = r9_electric_cut_bound(R7RecoveryCase(d), [0], [2])
    @test close["strict_threshold_excluded"] && !close["threshold_excluded"]
    exact =
        parse(BigInt, healthy["exact_energy_numerator"]) //
        parse(BigInt, healthy["exact_energy_denominator"])
    @test rationalize(BigInt, healthy["loss_lower_MWh"]; tol = 0) <= exact
    @test rationalize(BigInt, nextfloat(healthy["loss_lower_MWh"]); tol = 0) > exact
    d = deepcopy(c.data)
    d["probabilities"] = [0.25, 0.75]
    d["devices"][1]["previous_P_MW"] = [0.5, 0.5]
    d["devices"][2]["initial_MWh"] = [0.2, 0.2]
    d["heat"]["pipes"][1]["initial_S_K"] = [343.15, 343.15]
    d["heat"]["pipes"][1]["initial_R_K"] = [313.15, 313.15]
    push!(
        d["devices"],
        Dict(
            "id"=>"PV2",
            "kind"=>"PV",
            "electric_node"=>2,
            "P_max_MW"=>0.4,
            "available_MW"=>[[0.4, 0.0]],
        ),
    )
    cs = R7RecoveryCase(d)
    q = r9_electric_cut_bound(cs, [0], [2])
    @test q["loss_lower_MWh"] ≈ 0.25 atol=1e-14
    @test q["loss_lower_MWh"] ≈
          sum(d["probabilities"][w]*cut_transport_lp(cs, [0], 1, w) for w in 1:2) atol=1e-8
    @test length(q["rows"]) == 2
    reverse_data = deepcopy(c.data)
    reverse_data["electric"]["lines"][1]["from"] = 2
    reverse_data["electric"]["lines"][1]["to"] = 1
    @test r9_electric_cut_bound(R7RecoveryCase(reverse_data), [0], [2])["loss_lower_MWh"] ==
          healthy["loss_lower_MWh"]
end
