module R6EvaluationTests
using Test, PaperRebuild, JuMP, HiGHS, Clarabel, TOML, SHA
include(joinpath(@__DIR__, "..", "scripts", "r5_dispatch_cases.jl"))
const highs=optimizer_with_attributes(
    HiGHS.Optimizer,
    "primal_feasibility_tolerance"=>1e-9,
    "dual_feasibility_tolerance"=>1e-9,
)
const clarabel=optimizer_with_attributes(
    Clarabel.Optimizer,
    "tol_feas"=>1e-10,
    "tol_gap_abs"=>1e-10,
    "tol_gap_rel"=>1e-10,
)
const domain=Dict("building"=>Dict("lower_K"=>291.15, "upper_K"=>295.15))

@testset "R6-E1 common lexicographic recourse" begin
    c=R5DispatchCase(r5_dispatch_hand())
    b=build_r6_recourse(c, domain)
    @test termination_status(b.model)==MOI.OPTIMIZE_NOT_CALLED
    @test_throws ErrorException build_r6_recourse(c, domain; stage = :cost)
    @test_throws ErrorException build_r6_recourse(c, domain; stage = :hard, peak_cap = 0.1)
    @test_throws ErrorException build_r6_recourse(c, Dict())
    @test_throws ErrorException build_r6_recourse(
        c,
        Dict("building"=>Dict("lower_K"=>294.0, "upper_K"=>295.15)),
    )
    for optimizer in (highs, clarabel)
        r=evaluate_r6_day(c, domain; optimizer)
        println("R6 hard: ", r["status"])
        @test r["validation"]["policy_complete"]
        @test r["validation"]["comfort_outcome"]=="pass"
        @test Set(keys(r["stages"]))==Set(["hard"])
        @test r["validation"]["operating_net_cost"]≈14.2 atol=1e-5
        @test r["validation"]["delivery_budget_pass"]
        q=evaluate_r6_day(R5DispatchCase(r5_dispatch_hand(; dt = 0.25)), domain; optimizer)
        @test q["validation"]["operating_net_cost"]≈3.55 atol=1e-5
        # 既定H=0.042MW不足以保持20摄氏度；手算温降0.84/1.42 K。
        cold=r5_dispatch_hand()
        cold["ambient_K"]=[281.15]
        cold["buildings"][1]["terminal_rule"]="free"
        cold=R5DispatchCase(cold)
        r=evaluate_r6_day(cold, domain; optimizer)
        println("R6 cold: ", r["status"])
        @test r["stages"]["hard"]["status"]=="solver_infeasible"
        @test r["validation"]["model_pass"]
        @test r["validation"]["policy_complete"]
        @test r["validation"]["comfort_outcome"]=="violation"
        @test r["validation"]["peak_excess_K"]≈0.84/1.42 atol=1e-7
        @test r["validation"]["operating_net_cost"]≈14.2 atol=1e-5
        @test r["validation"]["stages"]["peak"]["peak_complete"]
        @test r["validation"]["stages"]["cost"]["kkt_pass"]
        bad=deepcopy(r)
        delete!(bad["stages"]["cost"], "raw_duals")
        @test !validate_r6_evaluation(cold, domain, bad)["policy_complete"]
        bad=deepcopy(r)
        bad["stages"]["cost"]["peak_cap_K"]+=0.1
        @test !validate_r6_evaluation(cold, domain, bad)["model_pass"]
        bad=deepcopy(r)
        bad["stages"]["peak"]["flat_values"]["peak"]+=0.1
        @test !validate_r6_evaluation(cold, domain, bad)["policy_complete"]
    end
end

@testset "R6-E1 failure and frozen boundaries" begin
    d=r5_dispatch_hand()
    d["ambient_K"]=[260.0]
    d["buildings"][1]["terminal_rule"]="free"
    r=evaluate_r6_day(R5DispatchCase(d), domain; optimizer = highs)
    @test r["status"]=="physical_model_infeasible"
    @test r["validation"]["comfort_outcome"]=="unknown"
    @test !r["validation"]["model_pass"]
    c=R5DispatchCase(r5_dispatch_hand())
    r=evaluate_r6_day(c, domain; optimizer = highs, budget_sec = 1e-12)
    @test occursin("budget_exhausted", r["status"])
    @test r["validation"]["comfort_outcome"]=="unknown"
    @test length(r["stages"])==1
    r=evaluate_r6_day(c, domain; optimizer = ()->error("license unavailable fixture"))
    @test r["status"]=="hard_stage_license_unavailable"
    @test length(r["stages"])==1
    @test_throws ErrorException evaluate_r6_day(c, domain; optimizer = highs, budget_sec = 0)
    s=R6EvaluationSpec()
    s.data["comfort_tolerance_K"]=0.1
    @test_throws ErrorException evaluate_r6_day(c, domain; optimizer = highs, spec = s)
end

@testset "R6-E3 evidence and contradictory status" begin
    c=R5DispatchCase(r5_dispatch_hand())
    original=evaluate_r6_day(c, domain; optimizer = highs)
    mktempdir() do dir
        path=joinpath(dir, "中文 日记录")
        save_r6_evaluation(c, domain, original, path)
        loaded=read_r6_evaluation(path)
        @test loaded.current_source_matches
        @test isequal(loaded.result, original)
        @test loaded.validation["policy_complete"]
        @test_throws ErrorException save_r6_evaluation(c, domain, original, path)
        open(joinpath(path, "result.toml"), "a") do io
            write(io, "\n# altered\n")
        end
        @test_throws ErrorException read_r6_evaluation(path)
    end
    peak=PaperRebuild.r6_evaluation_stage(c, domain, :peak, nothing, highs, time()+60)
    cost=PaperRebuild.r6_evaluation_stage(
        c,
        domain,
        :cost,
        peak["flat_values"]["peak"]+1e-8,
        highs,
        time()+60,
    )
    conflict=deepcopy(original)
    conflict["stages"]["hard"]=Dict(
        "case_sha256"=>c.sha256,
        "stage"=>"hard",
        "status"=>"solver_infeasible",
    )
    conflict["stages"]["peak"]=peak
    conflict["stages"]["cost"]=cost
    conflict["selected_stage"]="cost"
    @test !validate_r6_evaluation(c, domain, conflict)["policy_complete"]
end

@testset "R6-E2 preserve trained awards on unseen trajectories" begin
    root=normpath(joinpath(@__DIR__, ".."))
    p=load_r6_physical_case(joinpath(root, "configs", "r6", "daily-small.toml"))
    w=TOML.parsefile(
        joinpath(root, "results", "summaries", "r6-training-pilot-v1", "witnesses", "SP.toml"),
    )
    c=R5StrategicCase(w["case"])
    policy=r6_policy_from_training(p, c, w["result"])
    @test policy.data["physical_sha256"]==p.sha256
    @test [x["id"] for x in policy.data["support"]]==[x["id"] for x in c.data["risk"]["commitment"]["scenarios"]]
    for (i, s) in enumerate(policy.data["support"])
        point=permutedims(hcat(s["pv_fraction"], s["activation_signed"]))
        label=r6_support_label(policy, point)
        @test label["index"]==i
        @test label["distance"]==0
        @test label["label"]==0
    end
    values=zeros(2, 24)
    values[2, :].=0.5
    day=r6_evaluation_day(policy, values; id = "analytic_new_day")
    @test day.data["award"]["P_DA_MW"]==w["result"]["risk_policy"]["first_stage"]["P_DA_MW"]
    @test day.data["award"]["R_up_MW"]==w["result"]["risk_policy"]["first_stage"]["R_up_MW"]
    @test day.data["buildings"]==p.data["dispatch"]["buildings"]
    @test day.data["heat"]==p.data["dispatch"]["heat"]
    @test day.data["realtime"]["alpha_up"]==fill(0.5, 24)
    @test policy.data["day_ahead_net_payment_USD"]≈-182.66860455168944 atol=1e-8
    bad=deepcopy(policy)
    bad.data["award"]["P_DA_MW"][1]+=0.01
    @test_throws ErrorException r6_evaluation_day(bad, values; id = "bad")
    r=evaluate_r6_day(policy, values; id = "analytic_new_day", optimizer = highs)
    @test r["policy_sha256"]==policy.sha256
    @test r["trajectory_id"]=="analytic_new_day"
    @test r["validation"]["comfort_outcome"] in ("pass", "violation", "unknown")
    @test r["validation"]["day_ahead_cost"]≈policy.data["day_ahead_net_payment_USD"] atol=1e-8
end

# 明确的单元夹具：不是从真实训练结果取得，也不纳入正式统计。
function fixture_policy(label; ambient = 281.15)
    p=load_r6_physical_case(joinpath(@__DIR__, "..", "configs", "r6", "daily-small.toml"))
    d=deepcopy(p.data)
    day=r5_dispatch_hand()
    day["T"]=24
    day["ambient_K"]=fill(ambient, 24)
    for key in ("P_load_MW", "Q_load_Mvar")
        day["electric"][key]=[fill(only(row), 24) for row in day["electric"][key]]
    end
    for block in ("award", "realtime"), (key, value) in collect(day[block])
        value isa AbstractVector && (day[block][key]=fill(only(value), 24))
    end
    pv=deepcopy(only(filter(x->x["kind"]=="PV", d["dispatch"]["devices"])))
    pv["available_MW"]=zeros(24)
    push!(day["devices"], pv)
    day["buildings"][1]["terminal_rule"]="free"
    d["dispatch"]=day
    d["temperature_domain"]=deepcopy(domain)
    physical=R6PhysicalCase(d)
    data=Dict{String,Any}(
        "schema"=>"r6-policy-v1",
        "evaluation_version"=>"r6_support_nearest_v1",
        "physical"=>physical.data,
        "physical_sha256"=>physical.sha256,
        "award"=>deepcopy(day["award"]),
        "test_fixture"=>true,
        "support"=>[
            Dict(
                "id"=>"fixed_zero",
                "probability"=>1.0,
                "pv_fraction"=>zeros(24),
                "activation_signed"=>zeros(24),
                "label"=>label,
                "raw_z"=>Float64(label),
            ),
        ],
    )
    R6Policy(data, bytes2hex(sha256(PaperRebuild.r5_market_text(data))))
end

@testset "R6-E4 nearest policy and declared failure" begin
    trajectory=zeros(2, 24)
    hard=fixture_policy(0)
    relaxed=fixture_policy(1)
    for optimizer in (highs, clarabel)
        fail=evaluate_r6_policy_day(hard, trajectory; id = "cold_fixture", optimizer)
        @test fail["stage"]["stage"]=="hard"
        @test fail["status"]=="solver_infeasible"
        @test fail["validation"]["comfort_outcome"]=="unknown"
        @test !fail["validation"]["policy_complete"]
        @test !haskey(fail, "stages") # 不能暗中切换z或调用舒适诊断。
        wide=evaluate_r6_policy_day(relaxed, trajectory; id = "cold_fixture", optimizer)
        @test wide["validation"]["policy_complete"]
        @test wide["validation"]["comfort_outcome"]=="violation"
        @test wide["stage"]["stage"]=="physical"
        @test wide["validation"]["peak_excess_K"]≈2*(1-(1/1.42)^24) atol=1e-6
        @test wide["validation"]["operating_net_cost"]≈24*14.2 atol=1e-5
        ok=evaluate_r6_policy_day(
            fixture_policy(1; ambient = 283.15),
            trajectory;
            id = "warm_fixture",
            optimizer,
        )
        @test ok["validation"]["trained_label"]==1
        @test ok["validation"]["comfort_outcome"]=="pass" # 标签为1不代表一定违反。
        bad=deepcopy(wide)
        bad["stage"]["stage"]="hard"
        @test_throws ErrorException validate_r6_policy_day(relaxed, trajectory, bad)
        bad=deepcopy(wide)
        delete!(bad["stage"], "raw_duals")
        @test validate_r6_policy_day(relaxed, trajectory, bad)["comfort_outcome"]=="unknown"
    end
    tied=deepcopy(relaxed.data)
    tied["support"][1]["pv_fraction"].=0.0
    tied["support"][1]["activation_signed"].=-1.0
    twin=deepcopy(tied["support"][1])
    twin["id"]="second"
    twin["activation_signed"].=1.0
    twin["label"], twin["raw_z"]=0, 0.0
    push!(tied["support"], twin)
    policy=R6Policy(tied, bytes2hex(sha256(PaperRebuild.r5_market_text(tied))))
    match=r6_support_label(policy, trajectory)
    @test match["index"]==1
    @test match["label"]==1
    @test match["distance"]≈sqrt(0.125) atol=1e-12
    @test match["all_distances"][1]==match["all_distances"][2]
    @test_throws ErrorException r6_support_label(policy, fill(NaN, 2, 24))
    @test_throws ErrorException r6_support_label(policy, fill(2.0, 2, 24))
    @test_throws ErrorException r6_support_label(policy, zeros(2, 23))
    tiny=evaluate_r6_policy_day(
        relaxed,
        trajectory;
        id = "tiny",
        optimizer = highs,
        budget_sec = 1e-12,
    )
    @test tiny["validation"]["comfort_outcome"]=="unknown"
    @test tiny["status"]=="budget_exhausted_before_build"
    no_license=evaluate_r6_policy_day(
        relaxed,
        trajectory;
        id = "no_license",
        optimizer = ()->error("license fixture"),
    )
    @test no_license["status"]=="license_unavailable"
    @test !no_license["validation"]["model_pass"]
end

@testset "R6-E3 support policy archival and frozen replay" begin
    p=fixture_policy(1)
    v=zeros(2, 24)
    original=evaluate_r6_policy_day(p, v; id = "archive_fixture", optimizer = highs)
    mktempdir() do dir
        path=joinpath(dir, "中文 策略日")
        save_r6_policy_day(p, v, original, path)
        x=read_r6_policy_day(path)
        @test isequal(x.result, original)
        @test x.current_source_matches && x.validation["cost_complete"]
        @test x.policy.sha256==p.sha256
        @test x.trajectory==v
        @test_throws ErrorException save_r6_policy_day(p, v, original, path)
        @test_throws ErrorException read_r6_evaluation(path)
        # 冻结依赖须在新的模块可读；没有再次调用求解器。
        box=Module(gensym(:R6FrozenTest))
        Base.include(box, joinpath(path, "code", "replay.jl"))
        @test Base.invokelatest(getfield, box, :x).validation["comfort_outcome"]=="violation"
        open(joinpath(path, "trajectory.toml"), "a") do io
            write(io, "\n# changed\n")
        end
        @test_throws ErrorException read_r6_policy_day(path)
        bad=deepcopy(original)
        bad["validation"]["comfort_outcome"]="pass"
        @test_throws ErrorException save_r6_policy_day(p, v, bad, joinpath(dir, "bad"))
    end
end
end
