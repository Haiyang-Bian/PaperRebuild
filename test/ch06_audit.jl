using Test, JuMP, HiGHS, TOML
include(joinpath(@__DIR__, "..", "scripts", "audit_ch06.jl"))

@testset "R7 selected analytic audit, no dispatch implementation" begin
    w = ch06_audit_witnesses()
    @testset "R7-quantifiers and R7-shared-control" begin
        @test sum(w["quantifiers"]["weights"] .* w["quantifiers"]["loss_MWh"]) == 1
        @test maximum(w["quantifiers"]["loss_MWh"]) > w["quantifiers"]["limit_MWh"]
        @test w["shared_control"]["shared_value"] == 1
        @test w["shared_control"]["scenario_adaptive_value"] == 0
    end
    @testset "R7-switch and R7-fault-set" begin
        @test w["switch_factor"][1]["literal_allowance"] == 0
        @test w["switch_factor"][2]["adopted_allowance"] == 0
        @test w["failure_window"]["literal_allowed_gamma"] == [0]
        closed = only(filter(x -> x["base"] == 1 && x["fault"] == 0, w["switch_actions"]))
        @test closed["literal_actions"] == [[1, 0, 0]]
        opened = only(filter(x -> x["base"] == 0 && x["fault"] == 1, w["switch_actions"]))
        @test isempty(opened["literal_actions"])
        @test length(w["fault_sets"]["masks"]) == 11
        @test 0 in w["fault_sets"]["masks"]
    end
    @testset "R7-forest" begin
        @test length(w["forests"]) == 7
        for f in w["forests"]
            @test f["edges"] == f["adopted_edge_count"]
            @test f["edges"] != f["literal_edge_count"]
        end
    end
    @testset "R7-energy-datum and R7-energy-integration" begin
        e = w["energy_datum"]
        @test e["relative_energy_MWh"] ≈ 7/60
        @test e["maximum_energy_MWh"] ≈ 7/30
        @test e["reconstructed_K"] == e["initial_K"]
        @test e["literal_absolute_initial_MWh"] > e["maximum_energy_MWh"]
        @test e["literal_temperature_from_relative_K"] < e["lower_K"]
        for r in w["integration"]
            @test r["dt_h"]*r["steps"] == 1
            @test r["total_delta_MWh"] ≈ 0.07
            @test r["total_delta_MWh"] ≈ r["direct_balance_MWh"]
        end
    end
    @testset "R7-circulation-remainder" begin
        for r in w["circulation_remainder"]
            @test isapprox(r["difference_MW"], r["remainder_MW"]; atol = 1e-12)
        end
        @test minimum(r["remainder_MW"] for r in w["circulation_remainder"]) < 0
        @test maximum(r["remainder_MW"] for r in w["circulation_remainder"]) > 0
    end
    @testset "R7-dual" begin
        m = Model(HiGHS.Optimizer)
        # 沿用前序R6串行夹具的单线程池，避免Windows默认线程数与进程级调度器冲突。
        set_optimizer_attribute(m, "threads", 1)
        set_silent(m)
        @variable(m, r)
        c = @constraint(m, -r <= -2)
        @objective(m, Min, r)
        optimize!(m)
        @test termination_status(m) == MOI.OPTIMAL
        @test value(r) ≈ 2
        @test dual(c) ≈ -1
        @test -dual(c) ≈ 1
        @test -2dual(c) ≈ objective_value(m)
        literal = Model(HiGHS.Optimizer)
        set_optimizer_attribute(literal, "threads", 1)
        set_silent(literal)
        @variable(literal, π >= 0)
        @constraint(literal, -π >= 1)
        @objective(literal, Max, -2π)
        optimize!(literal)
        @test termination_status(literal) == MOI.INFEASIBLE
    end
    @testset "R7-bounds and R7-revision" begin
        b = w["inner_bounds"]
        @test b["exact_fault_values"] == [3, 4, 2]
        @test b["valid_lower"] < b["exact_worst"] < b["valid_upper"]
        @test b["literal_stop"] && !b["correct_stop"]
        @test !w["inexact_recovery"]["violation_proved"]
        @test !w["inexact_recovery"]["safety_proved"]
        @test w["revision"]["stale_flags_claim_safe"]
        @test !w["revision"]["same_revision_safe"]
        @test 0.6 > w["revision"]["limit"]
    end
    @testset "R7 audit saved values and claim tamper" begin
        mktempdir() do dir
            path = joinpath(dir, "proof.toml")
            save_ch06_audit(path)
            @test check_ch06_audit(path) === nothing
            @test_throws ErrorException save_ch06_audit(path)
            d = TOML.parsefile(path)
            d["witnesses"]["inner_bounds"]["exact_worst"] = 3
            write(path, ch06_audit_text(d))
            @test_throws ErrorException check_ch06_audit(path)
            d["witnesses"] = ch06_audit_witnesses()
            d["dispatch_implemented"] = true
            write(path, ch06_audit_text(d))
            @test_throws ErrorException check_ch06_audit(path)
        end
    end
end
