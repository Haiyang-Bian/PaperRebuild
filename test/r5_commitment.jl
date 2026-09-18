module R5CommitmentTests
using PaperRebuild, JuMP, HiGHS, Clarabel, TOML, Test
const PR=PaperRebuild
include(joinpath(@__DIR__, "..", "scripts", "r5_commitment_cases.jl"))
highs=optimizer_with_attributes(
    HiGHS.Optimizer,
    "primal_feasibility_tolerance"=>1e-9,
    "dual_feasibility_tolerance"=>1e-9,
)
clarabel=optimizer_with_attributes(
    Clarabel.Optimizer,
    "tol_feas"=>1e-10,
    "tol_gap_abs"=>1e-10,
    "tol_gap_rel"=>1e-10,
)

@testset "R5 shared commitment analytic and scenario KKT" begin
    for opt in (highs, clarabel), dt in (1.0, 0.25)
        c=R5CommitmentCase(r5_commitment_teaching(; dt))
        b=build_r5_commitment(c)
        @test termination_status(b.model)==MOI.OPTIMIZE_NOT_CALLED
        @test b.model_type=="continuous_LP"
        r=solve_r5_commitment(c; optimizer = opt)
        get(r, "status", "")=="execution_error"&&println(r["error"])
        @test r["status"]=="solver_optimal"
        @test r["validation"]["model_pass"]
        @test r["validation"]["kkt_pass"]
        @test r["cost_optimization_complete"]
        @test isapprox(r["solver_objective"], 2.085dt; atol = 1e-6)
        for (k, x) in (("P_DA_MW", 0.08), ("R_up_MW", 0.08), ("R_down_MW", 0.062))
            @test isapprox(only(r["first_stage"][k]), x; atol = 1e-7)
        end
        # 在原独立建模接口固定同一共同承诺，再求解各条件子问题。
        for s in c.data["scenarios"]
            view=PR.r5_commitment_view(c, s, r["first_stage"])
            separate=solve_r5_dispatch(view; optimizer = opt)
            saved=r["scenarios"][s["id"]]
            @test separate["validation"]["model_pass"]
            @test isapprox(separate["solver_objective"], saved["solver_objective"]; atol = 1e-5)
            @test r["validation"]["scenarios"][s["id"]]["kkt"]["kkt_pass"]
        end
    end
end

@testset "R5 shared commitment mechanisms and frozen future" begin
    inputs=r5_commitment_inputs()
    results=Dict{String,Any}()
    for name in (
        "no_reserve",
        "fixed_feasible",
        "overcommitted",
        "capacity_denominator",
        "no_call_only",
        "unequal_weights",
        "four_period",
        "four_period_future",
    )
        c=R5CommitmentCase(inputs[name])
        r=solve_r5_commitment(c; optimizer = highs)
        results[name]=r
        if name=="overcommitted"
            @test r["status"]=="solver_infeasible"
            @test !r["validation"]["model_pass"]
            @test !haskey(r, "first_stage")
        else
            @test r["validation"]["model_pass"]
            @test r["validation"]["kkt_pass"]
            @test r["cost_optimization_complete"]
        end
    end
    @test results["no_reserve"]["solver_objective"]≈14.2
    @test results["fixed_feasible"]["solver_objective"]≈2.085
    @test results["no_call_only"]["solver_objective"]≈-1.8
    @test results["capacity_denominator"]["solver_objective"]<=2.085+1e-6
    # 只看未调用情景会选择无法满足完整调用集合的容量；保留其条件可行性，不伪造可靠率。
    bad=deepcopy(inputs["hand"])
    for k in PR.R5_COMMITMENT_KEYS
        x=results["no_call_only"]["first_stage"][k]
        bad["bounds"][k]=Dict("lower"=>x, "upper"=>x)
    end
    r=solve_r5_commitment(R5CommitmentCase(bad); optimizer = highs)
    @test r["status"]=="solver_infeasible"
end

@testset "R5 shared commitment input, missing dual and persistence" begin
    d=r5_commitment_teaching()
    for change in (:probability, :zero, :history, :capacity, :undeclared, :price, :bounds, :risk)
        x=deepcopy(d)
        s=x["scenarios"][2]
        if change==:probability
            s["probability"]=0.3
        elseif change==:zero
            s["probability"]=0.0
        elseif change==:history
            s["case"]["heat"]["pipes"][1]["history_S_K"][1]+=1
        elseif change==:capacity
            s["case"]["devices"][2]["p_max_MW"]+=0.1
        elseif change==:undeclared
            s["case"]["ambient_K"][1]-=1
        elseif change==:price
            x["day_ahead"]["up_price"]=[NaN]
        elseif change==:bounds
            x["bounds"]["R_up_MW"]["upper"]=[Inf]
        else
            x["comfort"]="joint_chance"
        end
        @test_throws ErrorException R5CommitmentCase(x)
    end
    c=R5CommitmentCase(d)
    r=solve_r5_commitment(c; optimizer = highs)
    for target in (:weighted, :first, :conditional, :candidate)
        x=deepcopy(r)
        if target==:weighted
            delete!(x, "weighted_raw_scenario_duals")
        elseif target==:first
            x["raw_first_stage_duals"]["PCC-up/1"]+=10
        elseif target==:conditional
            x["scenarios"]["up"]["raw_constraint_duals"]["R5-D-delivery/PCC/1"]+=1
        else
            x["first_stage"]["P_DA_MW"]=[NaN]
        end
        @test !validate_r5_commitment(c, x)["kkt_pass"]
    end
    short=solve_r5_commitment(c; optimizer = highs, budget_sec = 1e-12)
    @test short["status"]=="budget_exhausted_before_solve"
    @test !short["cost_optimization_complete"]
    @test_throws ErrorException solve_r5_commitment(c; optimizer = highs, budget_sec = -1)
    unavailable=solve_r5_commitment(c; optimizer = ()->error("license unavailable synthetic test"))
    @test unavailable["status"]=="license_unavailable"
    @test !unavailable["validation"]["model_pass"]
    unsupported=solve_r5_commitment(
        c;
        optimizer = ()->throw(MOI.UnsupportedAttribute(MOI.TimeLimitSec())),
    )
    @test unsupported["status"]=="unsupported_solver"
    @test !unsupported["cost_optimization_complete"]
    mktempdir() do dir
        path=save_r5_commitment_run(c, r, joinpath(dir, "run"))
        saved=read_r5_commitment_run(path)
        @test saved.case.sha256==c.sha256
        @test saved.validation["kkt_pass"]
        @test_throws ErrorException save_r5_commitment_run(c, r, path)
        open(joinpath(path, "result.toml"), "a") do io
            write(io, "\n# tampered\n")
        end
        @test_throws ErrorException read_r5_commitment_run(path)
    end
end

@testset "R5 shared commitment nonanticipation and probability invariance" begin
    d=r5_commitment_teaching()
    total=0.0
    for s in d["scenarios"]
        single=deepcopy(d)
        single["scenarios"]=[deepcopy(s)]
        single["scenarios"][1]["probability"]=1.0
        r=solve_r5_commitment(R5CommitmentCase(single); optimizer = highs)
        @test r["validation"]["optimality_pass"]
        total+=s["probability"]*r["solver_objective"]
    end
    # 每个情景都可提前改承诺的完美信息下界，与真实共同承诺严格分开。
    @test isapprox(total, -1.35; atol = 1e-6)
    @test total<2.085
    reverse=deepcopy(d)
    reverse["scenarios"]=reverse["scenarios"][[3, 2, 1]]
    split=deepcopy(d)
    split["scenarios"][1]["probability"]=0.25
    copy_s=deepcopy(split["scenarios"][1])
    copy_s["id"]="none_copy"
    push!(split["scenarios"], copy_s)
    for raw in (reverse, split)
        r=solve_r5_commitment(R5CommitmentCase(raw); optimizer = clarabel)
        @test r["validation"]["kkt_pass"]
        @test isapprox(r["solver_objective"], 2.085; atol = 1e-6)
    end
end
end
