module R6StudyTests
using Test, PaperRebuild, TOML, SHA
include(joinpath(@__DIR__, "..", "scripts", "r6_study.jl"))
const rule=load_r6_study(joinpath(@__DIR__, "..", "configs", "r6", "study.toml"))

function good_day(cost; violation = false)
    Dict{String,Any}(
        "model_pass"=>true,
        "cost_complete"=>true,
        "policy_complete"=>true,
        "comfort_outcome"=>violation ? "violation" : "pass",
        "operating_net_cost"=>cost,
        "peak_excess_K"=>violation ? 0.2 : 0.0,
        "delivery_budget_pass"=>true,
        "called_energy_MWh"=>1.0,
        "mismatch_MWh"=>0.1,
    )
end
const ids=["validation_"*lpad(i, 4, '0') for i in 1:500]
function records_fixture()
    Dict(
        c["id"]=>Dict(
            "split"=>"validation",
            "candidate"=>c,
            "summary"=>r6_summarize_days(
                ids,
                [good_day(100-c["order"]) for _ in ids];
                epsilon = 0.05,
            ),
        ) for c in r6_study_candidates(rule)
    )
end

@testset "R6-F1 frozen design and honest unknowns" begin
    candidates=r6_study_candidates(rule)
    @test length(candidates)==14
    @test [c["radius"] for c in candidates if c["method"]=="DRJCC"]==[0, 0.0005, 0.001, 0.005, 0.01]
    @test length(unique(c["id"] for c in candidates))==14
    @test rule.data["source_policy"]=="committed_and_snapshotted_before_first_solve"
    bad=deepcopy(rule.data)
    bad["radii"]=[0.0, 0.1]
    @test_throws ErrorException R6StudySpec(bad)
    bad=deepcopy(rule.data)
    bad["physical"]="../other.toml"
    @test_throws ErrorException R6StudySpec(bad)
    bad=deepcopy(rule.data)
    bad["test_days"]=999
    @test_throws ErrorException R6StudySpec(bad)
    bad=deepcopy(rule.data)
    bad["solver_parameters"]["gurobi"]["MIPGap"]=0.01
    @test_throws ErrorException R6StudySpec(bad)
    @test_throws ErrorException r6_summarize_days(
        ["same", "same"],
        [good_day(2), good_day(3)];
        epsilon = 0.05,
    )
    s=r6_summarize_days(["a", "b"], [good_day(-5), r6_study_unknown()]; epsilon = 0.05)
    @test s["missing_cost_days"]==1 && s["risk"]["unknown"]==1
    @test s["risk"]["n"]==2
    @test isnan(s["mean_net_cost_USD"])
    @test s["observed_mean_net_cost_USD"]==-5
    @test s["model_days_relative_mismatch"]≈0.1
    bad=good_day(1)
    bad["cost_complete"]=false
    @test_throws ErrorException r6_summarize_days(["a"], [bad]; epsilon = 0.05)
    vals=[good_day(100-i) for i in 1:500]
    s=r6_summarize_days(ids, vals; epsilon = 0.05)
    @test s["all_costs_complete"] && s["risk"]["status"]=="supported"
    @test s["mean_net_cost_USD"]≈-150.5
    @test s["observed_cost_quantiles_USD"]["q50"]≈-150.5
    @test r6_study_solver(rule, "highs") isa MOI.OptimizerWithAttributes
    @test_throws ErrorException r6_study_solver(rule, "unknown")
    mktempdir() do dir
        @test_throws ErrorException freeze_r6_study(dir)
        path=joinpath(dir, "atomic.toml")
        r6_study_new(path, Dict("x"=>1))
        @test_throws ErrorException r6_study_new(path, Dict("x"=>2))
        @test TOML.parsefile(path)["x"]==1
    end
end

@testset "R6-F2 validation selection and locked failure" begin
    rows=records_fixture()
    x=select_r6_methods(rule, rows)
    @test !x["test_used"] && x["source_split"]=="validation"
    @test length(x["selected"])==6
    @test all(z["validated"] for z in x["selected"])
    @test only(filter(z->z["method"]=="DRJCC", x["selected"]))["radius"]==0.01
    bad=deepcopy(rows)
    delete!(bad, "SP")
    @test_throws ErrorException select_r6_methods(rule, bad)
    bad=deepcopy(rows)
    bad["SP"]["split"]="test"
    @test_throws ErrorException select_r6_methods(rule, bad)
    bad=deepcopy(rows)
    bad["SP"]["summary"]["ids_sha256"]="different"
    @test_throws ErrorException select_r6_methods(rule, bad)
    bad=deepcopy(rows)
    bad["SP"]["summary"]["risk"]["upper"]=0.0
    @test_throws ErrorException select_r6_methods(rule, bad)
    bad=deepcopy(rows)
    bad["SP"]["summary"]["n"]=499
    @test_throws ErrorException select_r6_methods(rule, bad)
    for c in r6_study_candidates(rule)
        c["method"]=="DRJCC" || continue
        rows[c["id"]]["summary"]=r6_summarize_days(ids, [good_day(5) for _ in ids]; epsilon = 0.05)
    end
    tied=select_r6_methods(rule, rows)
    @test only(filter(z->z["method"]=="DRJCC", tied["selected"]))["radius"]==0.0
    for c in r6_study_candidates(rule)
        c["method"]=="DRO" || continue
        vals=[good_day(1; violation = true) for _ in ids]
        c["radius"]==0.001 && (vals[1:100]=[good_day(3) for _ in 1:100])
        rows[c["id"]]["summary"]=r6_summarize_days(ids, vals; epsilon = 0.05)
    end
    fallback=only(filter(z->z["method"]=="DRO", select_r6_methods(rule, rows)["selected"]))
    @test !fallback["validated"]
    @test fallback["radius"]==0.001
    @test fallback["status"]=="fallback_not_validation_supported"
    rows["D"]["summary"]=r6_summarize_days(ids, [r6_study_unknown() for _ in ids]; epsilon = 0.05)
    unknown=only(filter(z->z["method"]=="D", select_r6_methods(rule, rows)["selected"]))
    @test !unknown["validated"] && unknown["validation_summary"]["risk"]["unknown"]==500
end

@testset "R6-F3 immutable evidence and deterministic stress" begin
    root=normpath(joinpath(@__DIR__, ".."))
    protocol=load_r6_protocol(joinpath(root, "configs", "r6", "protocol.toml"))
    s=r6_study_stress_set(rule, protocol)
    @test size(s.values)==(2, 24, 4)
    @test all(iszero, s.values[1, :, 1:2])
    @test s.values[1, :, 3]==protocol.data["generator"]["clear_sky_fraction"]
    @test all(==(1.0), s.values[2, :, 1]) && all(==(-1.0), s.values[2, :, 2])
    @test s.sha256==r6_study_stress_set(rule, protocol).sha256
    stress=r6_study_summary((; spec = rule), "stress", s, [r6_study_unknown() for _ in s.ids])
    @test !haskey(stress, "risk") && stress["n"]==4
    @test stress["scope"]=="deterministic_cases_no_probability_claim"
    mktempdir() do dir
        source=joinpath(dir, "source")
        mkdir(source)
        write(joinpath(source, "a.jl"), "x=1\n")
        tar=joinpath(dir, "source.tar")
        Tar.create(source, tar)
        hashes=Dict("a.jl"=>r6_study_hash(joinpath(source, "a.jl")))
        @test r6_study_check_archive(read(tar), hashes)
        write(joinpath(source, "a.jl"), "x=2\n")
        @test_throws ErrorException r6_study_assert_sources(source, Dict("sources"=>hashes))
        @test_throws ErrorException r6_study_check_archive(read(tar), Dict("a.jl"=>"altered"))
        @test_throws Exception r6_study_selection(dir, (; spec = rule), Dict())
    end
    # 只复用旧训练支持作为接口夹具，不读取正式验证/测试轨迹来调整规则。
    p=load_r6_physical_case(joinpath(root, "configs", "r6", "daily-small.toml"))
    witness=TOML.parsefile(
        joinpath(root, "results", "summaries", "r6-training-pilot-v1", "witnesses", "SP.toml"),
    )
    policy=r6_policy_from_training(p, R5StrategicCase(witness["case"]), witness["result"])
    point=policy.data["support"][1]
    trajectory=permutedims(hcat(point["pv_fraction"], point["activation_signed"]))
    day="validation_0001"
    # HiGHS共享全局调度器。旧串行测试曾用默认线程，切换本批固定1线程前按其API释放。
    # 此处没有并行求解；正式CLI在独立进程中始终使用同一线程数，不执行隐式失败重试。
    HiGHS.Highs_resetGlobalScheduler(1)
    result=evaluate_r6_policy_day(
        policy,
        trajectory;
        id = day,
        optimizer = r6_study_solver(rule, "highs"),
    )
    compact=r6_study_compact(result["validation"])
    println("R6-F3 support point status=", result["status"])
    @test compact["model_pass"] && compact["cost_complete"]
    delete!(result, "validation")
    mktempdir() do dir
        candidate=only(filter(c->c["id"]=="SP", r6_study_candidates(rule)))
        sample=(;
            ids = [day],
            values = reshape(copy(trajectory), 2, 24, 1),
            sha256 = "unit-test-support",
        )
        ctx=(; spec = rule, data = (; sets = Dict("validation"=>sample)))
        trained=(; record = Dict("result_sha256"=>"training-fixture"), policy)
        path=joinpath(dir, "validation", "SP", "days", day*".toml")
        r6_study_new(
            path,
            Dict(
                "schema"=>"r6-study-day-v1",
                "split"=>"validation",
                "set_sha256"=>sample.sha256,
                "candidate_id"=>"SP",
                "result"=>result,
                "validation"=>compact,
            ),
        )
        @test isequal(r6_study_day_read(path, policy, trajectory).validation, compact)
        summary=Dict(
            "candidate"=>candidate,
            "split"=>"validation",
            "set_sha256"=>sample.sha256,
            "training_result_sha256"=>"training-fixture",
            "training_candidate_accepted"=>true,
            "days"=>Dict(day=>r6_study_hash(path)),
            "summary"=>r6_study_summary(ctx, "validation", sample, [compact]),
        )
        summarypath=joinpath(dir, "validation", "SP", "summary.toml")
        r6_study_new(summarypath, summary)
        @test isequal(r6_study_checked_summary(dir, "validation", candidate, ctx, trained), summary)
        bad=deepcopy(summary)
        bad["summary"]["mean_net_cost_USD"]+=1
        write(summarypath, r6_study_text(bad))
        @test_throws ErrorException r6_study_checked_summary(
            dir,
            "validation",
            candidate,
            ctx,
            trained,
        )
        write(summarypath, r6_study_text(summary))
        altered=TOML.parsefile(path)
        altered["validation"]["operating_net_cost"]+=1
        write(path, r6_study_text(altered))
        @test_throws ErrorException r6_study_day_read(path, policy, trajectory)
        @test_throws ErrorException r6_study_checked_summary(
            dir,
            "validation",
            candidate,
            ctx,
            trained,
        )
    end
end
end
