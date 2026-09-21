module R9EvaluationTests
using Test, PaperRebuild, JuMP, HiGHS, Clarabel, TOML, SHA
include(joinpath(@__DIR__, "..", "scripts/r5_dispatch_cases.jl"))
include(joinpath(@__DIR__, "..", "scripts/r5_risk_cases.jl"))
const highs = optimizer_with_attributes(
    HiGHS.Optimizer,
    "threads"=>1,
    "output_flag"=>false,
    "primal_feasibility_tolerance"=>1e-9,
    "dual_feasibility_tolerance"=>1e-9,
)
const clarabel = optimizer_with_attributes(
    Clarabel.Optimizer,
    "verbose"=>false,
    "tol_feas"=>1e-10,
    "tol_gap_abs"=>1e-10,
    "tol_gap_rel"=>1e-10,
)

function pv_device(T)
    Dict{String,Any}(
        "id"=>"PV",
        "kind"=>"PV",
        "node"=>2,
        "p_min_MW"=>0.0,
        "p_max_MW"=>0.08,
        "q_min_Mvar"=>0.0,
        "q_max_Mvar"=>0.0,
        "cost_USD_MWh"=>5.0,
        "available_MW"=>zeros(T),
    )
end
function fixture(label; ambient = 283.15, dt = 1.0)
    c = r5_dispatch_hand(; dt)
    c["ambient_K"] = [ambient]
    c["buildings"][1]["terminal_rule"] = "free"
    push!(c["devices"], pv_device(1))
    R9ReservePolicy(
        Dict(
            "schema"=>"r9-reserve-policy-v1",
            "evaluation_version"=>"r9_nearest_recourse_v1",
            "information"=>"complete_trajectory",
            "currency"=>"USD",
            "template"=>c,
            "temperature_domain"=>Dict("building"=>Dict("lower_K"=>291.15, "upper_K"=>295.15)),
            "support"=>[
                Dict(
                    "id"=>"first",
                    "probability"=>0.5,
                    "pv_fraction"=>[0.0],
                    "activation_signed"=>[0.0],
                    "label"=>label,
                    "raw_z"=>Float64(label),
                ),
                Dict(
                    "id"=>"second",
                    "probability"=>0.5,
                    "pv_fraction"=>[1.0],
                    "activation_signed"=>[0.0],
                    "label"=>1-label,
                    "raw_z"=>Float64(1-label),
                ),
            ],
            "training"=>Dict("scheme"=>"analytic_fixture", "test_fixture"=>true),
        ),
    )
end

@testset "R9-OS1 and R9-OS2 locked operation, nearest branch and units" begin
    for n in (1, 64, 4096)
        data = Dict("unicode"=>repeat("电热α", n))
        @test PaperRebuild.r9_evaluation_hash(data) ==
              bytes2hex(sha256(PaperRebuild.r5_market_text(data)))
    end
    large = Dict("trajectory"=>repeat("温度与备用", 100000))
    mktemp() do path, io
        write(io, PaperRebuild.r5_market_text(large))
        close(io)
        @test PaperRebuild.r9_evaluation_hash(large) == bytes2hex(open(sha256, path))
    end
    p = fixture(0)
    original = deepcopy(p.data)
    @test r9_reserve_support_label(p, zeros(2, 1))["index"] == 1
    @test r9_reserve_support_label(p, reshape([1.0, 0.0], 2, 1))["index"] == 2
    @test r9_reserve_support_label(p, reshape([0.5, 0.0], 2, 1))["index"] == 1
    @test r9_reserve_support_label(p, reshape([0.5, 0.0], 2, 1))["distance"] ≈ 0.5/sqrt(2)
    day = r9_reserve_evaluation_day(p, reshape([0.75, -0.5], 2, 1); id = "new")
    @test day.data["award"] == p.data["template"]["award"]
    @test day.data["heat"] == p.data["template"]["heat"]
    @test day.data["realtime"]["alpha_down"] == [0.5]
    @test day.data["devices"][end]["available_MW"] == [0.06]
    @test p.data == original
    qdata = deepcopy(p.data)
    qdata["training"]["scheme"] = "different_parent"
    q = R9ReservePolicy(qdata)
    @test p.sha256 != q.sha256 && p.operation_sha256 == q.operation_sha256
    qdata["template"]["award"]["energy_price"][1] += 1
    @test R9ReservePolicy(qdata).operation_sha256 != p.operation_sha256
    qdata = deepcopy(p.data)
    qdata["support"][1]["label"] = 1
    qdata["support"][1]["raw_z"] = 1.0
    @test R9ReservePolicy(qdata).operation_sha256 != p.operation_sha256
    for x in (ones(3, 1), reshape([1.1, 0.0], 2, 1), reshape([0.0, NaN], 2, 1))
        @test_throws ErrorException r9_reserve_support_label(p, x)
    end
    bad = deepcopy(p)
    bad.data["template"]["award"]["P_DA_MW"][1] += 0.01
    @test_throws ErrorException r9_reserve_evaluation_day(bad, zeros(2, 1); id = "bad")
    for key in ("currency", "information")
        bad = deepcopy(p.data)
        bad[key] = "bad"
        @test_throws ErrorException R9ReservePolicy(bad)
    end
    bad = deepcopy(p.data)
    bad["support"][1]["raw_z"] = 0.5
    @test_throws ErrorException R9ReservePolicy(bad)
end

@testset "R9-OS3 and R9-OS4 exact operation, unknown and persistence" begin
    x = zeros(2, 1)
    values = Float64[]
    for opt in (highs, clarabel)
        p = fixture(0)
        r = evaluate_r9_reserve_day(p, x; id = "hand", optimizer = opt)
        @test r["validation"]["model_pass"] && r["validation"]["cost_complete"]
        @test r["validation"]["comfort_outcome"] == "pass"
        @test r["validation"]["operating_net_cost"] ≈ 14.2 atol=1e-5
        push!(values, r["validation"]["operating_net_cost"])
        q = evaluate_r9_reserve_day(fixture(0; dt = 0.25), x; id = "quarter", optimizer = opt)
        @test q["validation"]["operating_net_cost"] ≈ 3.55 atol=1e-5
        hard =
            evaluate_r9_reserve_day(fixture(0; ambient = 281.15), x; id = "cold", optimizer = opt)
        @test hard["status"] == "solver_infeasible" &&
              hard["validation"]["comfort_outcome"] == "unknown"
        wide =
            evaluate_r9_reserve_day(fixture(1; ambient = 281.15), x; id = "cold", optimizer = opt)
        @test wide["validation"]["cost_complete"] &&
              wide["validation"]["comfort_outcome"] == "violation"
        @test wide["validation"]["peak_excess_K"] ≈ 0.84/1.42 atol=1e-7
        bad = deepcopy(r)
        empty!(bad["stage"]["raw_duals"])
        @test validate_r9_reserve_day(p, x, bad)["comfort_outcome"] == "unknown"
        bad = deepcopy(r)
        bad["stage"]["stage"] = "physical"
        @test_throws ErrorException validate_r9_reserve_day(p, x, bad)
        mktempdir() do dir
            out = joinpath(dir, "day")
            save_r9_reserve_day(p, x, r, out)
            got = read_r9_reserve_day(out)
            @test got.policy.sha256 == p.sha256 && got.trajectory == x
            @test got.validation["cost_complete"]
            @test_throws ErrorException save_r9_reserve_day(p, x, r, out)
            open(io->write(io, "altered"), joinpath(out, "result.toml"), "a")
            @test_throws ErrorException read_r9_reserve_day(out)
        end
    end
    @test abs(values[1]-values[2])/max(1.0, abs(values[1])) < 1e-4
    p = fixture(0)
    tiny = evaluate_r9_reserve_day(p, x; id = "budget", optimizer = highs, budget_sec = 1e-12)
    @test occursin("budget_exhausted", tiny["status"]) &&
          tiny["validation"]["comfort_outcome"] == "unknown"
    failed = evaluate_r9_reserve_day(
        p,
        x;
        id = "license",
        optimizer = ()->error("license unavailable fixture"),
    )
    @test failed["status"] == "license_unavailable" &&
          failed["validation"]["comfort_outcome"] == "unknown"
    @test_throws ErrorException evaluate_r9_reserve_day(
        p,
        x;
        id = "invalid",
        optimizer = highs,
        budget_sec = 0,
    )
    risk = r6_risk_evidence([:pass, :violation, :unknown]; epsilon = 0.05)
    @test risk["n"] == 3 && risk["unknown"] == 1 && risk["violations"] == 1
end

@testset "R9-OS1 and R9-OS3 explicit CNY and compact replay" begin
    d = deepcopy(fixture(0).data)
    d["currency"] = "CNY"
    c = d["template"]
    c["schema"] = "r5-dispatch-case-v2"
    c["currency"] = "CNY"
    c["units"]["energy_price"] = "CNY/MWh"
    c["units"]["reserve_price"] = "CNY/(MW*h)"
    for g in c["devices"]
        g["cost_per_MWh"] = pop!(g, "cost_USD_MWh")
    end
    c["realtime"]["penalty_per_MWh"] = pop!(c["realtime"], "penalty_USD_MWh")
    # 显式同数值教学价格，不使用汇率转换。
    p = R9ReservePolicy(d)
    x = zeros(2, 1)
    r = evaluate_r9_reserve_day(p, x; id = "cny", optimizer = highs)
    @test r["currency"] == r["validation"]["currency"] == "CNY"
    @test r["validation"]["cost_complete"] && r["validation"]["operating_net_cost"] ≈ 14.2
    @test !haskey(r["validation"]["stage"]["lp"], "rows")
    @test r["validation"]["stage"]["lp"]["row_count"] > 0
    full = validate_r9_reserve_day(p, x, r)
    @test all(row["pass"] for row in full["stage"]["lp"]["rows"])
    unknown = Dict(
        "currency"=>"CNY",
        "comfort_outcome"=>"unknown",
        "cost_complete"=>false,
        "model_pass"=>false,
        "kkt_pass"=>false,
    )
    summary =
        summarize_r9_reserve_days(["done", "missing"], [r["validation"], unknown]; currency = "CNY")
    @test summary["risk"]["n"] == 2 && summary["risk"]["unknown"] == 1
    @test isnan(summary["mean_operating_net_cost"]) && summary["complete_cost_days"] == 1
    @test summary["observed_mean_operating_net_cost"] ≈ 14.2
    @test_throws ErrorException summarize_r9_reserve_days(
        ["done"],
        [r["validation"]];
        currency = "USD",
    )
    mktempdir() do dir
        out = joinpath(dir, "cny")
        save_r9_reserve_day(p, x, r, out)
        got = read_r9_reserve_day(out)
        @test got.validation["currency"] == "CNY" && got.validation["cost_complete"]
        bad = deepcopy(r)
        bad["validation"]["model_pass"] = false
        @test_throws ErrorException save_r9_reserve_day(p, x, bad, joinpath(dir, "false"))
    end
end

@testset "R9-OS1 extraction requires actual verified training" begin
    b = TOML.parsefile(joinpath(@__DIR__, "..", "configs/r5/commitment/hand.toml"))
    push!(b["uncertain_fields"], "devices.available_MW")
    for s in b["scenarios"]
        push!(s["case"]["devices"], pv_device(1))
    end
    c = R5RiskCase(r5_risk_case(b; name = "r9_policy_training"))
    r = solve_r5_risk(
        c;
        optimizer = highs,
        oracle_optimizer = highs,
        pattern = zeros(Int, length(b["scenarios"])),
    )
    p = r9_reserve_policy_from_training(c, r)
    @test p.data["training"]["run_id"] == r["run_id"]
    @test p.data["template"]["award"]["P_DA_MW"] == r["first_stage"]["P_DA_MW"]
    @test p.data["template"]["award"]["energy_price"] ==
          c.data["commitment"]["day_ahead"]["energy_price"]
    bad = deepcopy(r)
    bad["first_stage"]["P_DA_MW"][1] += 1
    @test_throws ErrorException r9_reserve_policy_from_training(c, bad)
    for variant in ("unsupported_uncertainty", "simultaneous_call")
        d = deepcopy(c.data)
        if variant == "unsupported_uncertainty"
            push!(d["commitment"]["uncertain_fields"], "ambient_K")
        else
            for s in d["commitment"]["scenarios"]
                s["case"]["realtime"]["alpha_up"] .= 0.2
                s["case"]["realtime"]["alpha_down"] .= 0.2
            end
        end
        @test_throws ErrorException r9_reserve_policy_from_training(R5RiskCase(d), r)
    end
end
end
