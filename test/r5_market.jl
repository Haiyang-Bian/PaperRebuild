module R5MarketTests
using Test, JuMP, HiGHS, Clarabel, TOML
using PaperRebuild
const RM=PaperRebuild
root=normpath(joinpath(@__DIR__, ".."))
base=RM.load_r5_market_case(joinpath(root, "configs", "r5", "market-base.toml"))
highs=optimizer_with_attributes(
    HiGHS.Optimizer,
    "primal_feasibility_tolerance"=>1e-9,
    "dual_feasibility_tolerance"=>1e-9,
)
# 同进程完整回归已有HiGHS全局线程池；测试沿用它，不能中途改为1线程。
# 正式研究用独立Julia进程，并在首个HiGHS实例中固定1线程，见r5_market_setup.jl。
clarabel=optimizer_with_attributes(
    Clarabel.Optimizer,
    "tol_feas"=>1e-10,
    "tol_gap_abs"=>1e-10,
    "tol_gap_rel"=>1e-10,
)
function hand_case(dt = 1.0)
    d=deepcopy(base.data)
    d["name"]="single-bus-hand"
    d["nodes"]=1
    d["T"]=1
    d["dt_h"]=dt
    d["network"]=Dict("slack_node"=>1, "ptdf"=>Any[], "limit_MW"=>Float64[])
    d["load_MW"]=[[50.0]]
    d["reserve_up_MW"]=[20.0]
    d["reserve_down_MW"]=[10.0]
    g=deepcopy(d["generators"][1])
    merge!(
        g,
        Dict(
            "node"=>1,
            "p_max"=>200.0,
            "p_bid_max"=>200.0,
            "p_initial"=>80.0,
            "ramp_up_MW_h"=>200.0,
            "ramp_down_MW_h"=>200.0,
            "up_max"=>100.0,
            "down_max"=>100.0,
            "energy_bid"=>20.0,
            "up_bid"=>5.0,
            "down_bid"=>2.0,
        ),
    )
    d["generators"]=[g]
    a=deepcopy(d["ies"][1])
    merge!(
        a,
        Dict(
            "node"=>1,
            "q_max"=>100.0,
            "energy_bid"=>100.0,
            "up_bid"=>2.0,
            "down_bid"=>3.0,
            "up_max"=>0.0,
            "down_max"=>0.0,
        ),
    )
    d["ies"]=[a]
    RM.R5MarketCase(d)
end
@testset "R5 market primal, dual and units" begin
    for optimizer in (highs, clarabel)
        hand=hand_case()
        r=RM.solve_r5_market(hand; optimizer)
        println(get(r, "error", "hand: "*r["status"]))
        @test r["validation"]["model_pass"]
        @test r["validation"]["kkt_pass"]
        @test r["cost_optimization_complete"]
        if haskey(r, "values")
            @test r["values"]["P_G"][1][1]≈80 atol=1e-5
            @test r["solver_objective"]≈-1280 atol=1e-4
            @test r["validation"]["LMP_USD_MWh"][1][1]≈20 atol=1e-5
            @test r["validation"]["reserve_up_price"][1]≈5 atol=1e-5
            @test r["validation"]["reserve_down_price"][1]≈2 atol=1e-5
            short=RM.solve_r5_market(hand_case(0.25); optimizer)
            @test short["solver_objective"]≈r["solver_objective"]/4 atol=1e-5
            @test short["validation"]["LMP_USD_MWh"][1][1]≈20 atol=1e-5
        end
        for c in (hand, base)
            primal=RM.solve_r5_market(c; optimizer)
            println(get(primal, "error", c.data["name"]*": "*primal["status"]))
            @test primal["validation"]["optimality_pass"]
            dual=RM.build_r5_market_dual(c; optimizer)
            set_silent(dual.model)
            set_time_limit_sec(dual.model, 60.0)
            optimize!(dual.model)
            @test termination_status(dual.model)==MOI.OPTIMAL
            @test objective_value(dual.model)≈primal["solver_objective"] atol=1e-4
            all(F in (VariableRef, AffExpr) for (F, S) in list_of_constraint_types(dual.model)) ||
                error("对偶实际不是线性模型")
        end
    end
    r=RM.solve_r5_market(base; optimizer = highs)
    @test r["validation"]["model_pass"]
    @test r["validation"]["kkt_pass"]
    @test all(abs(x-30)<=1e-5 for x in r["values"]["P_IES"][1])
    @test all(abs(x-15)<=1e-5 for x in r["values"]["R_IES_up"][1])
    for h in (1e-2, 1e-3, 1e-4)
        d=deepcopy(base.data)
        d["load_MW"][2][3]+=h
        trial=RM.solve_r5_market(RM.R5MarketCase(d); optimizer = highs)
        slope=(trial["solver_objective"]-r["solver_objective"])/h
        @test slope≈r["validation"]["LMP_USD_MWh"][2][3] rtol=1e-3
    end
    bad=deepcopy(r)
    bad["values"]["P_G"][1][1]+=1
    @test !RM.validate_r5_market(base, bad)["model_pass"]
    bad=deepcopy(r)
    bad["multipliers"]["energy"][1]*=-1
    @test !RM.validate_r5_market(base, bad)["kkt_pass"]
    bad=deepcopy(r)
    bad["raw_duals"]["energy"][1]+=1
    @test !RM.validate_r5_market(base, bad)["kkt_pass"]
    short=RM.solve_r5_market(base; optimizer = highs, budget_sec = 1e-9)
    @test short["status"]=="budget_exhausted_before_solve"
    @test !haskey(short, "values")
    over=deepcopy(base.data)
    over["load_MW"][2].+=1000.0
    failed=RM.solve_r5_market(RM.R5MarketCase(over); optimizer = highs)
    @test failed["status"]=="solver_infeasible"
    @test !haskey(failed, "values")
    noies=deepcopy(base.data)
    noies["ies"]=Any[]
    emptyresult=RM.solve_r5_market(RM.R5MarketCase(noies); optimizer = highs)
    println(get(emptyresult, "error", "empty IES: "*emptyresult["status"]))
    @test emptyresult["validation"]["optimality_pass"]
    @test_throws ErrorException RM.solve_r5_market(base; optimizer = highs, budget_sec = 0)
    invalid=deepcopy(base.data)
    invalid["network"]["ptdf"][1][1]=1
    @test_throws ErrorException RM.R5MarketCase(invalid)
    invalid=deepcopy(base.data)
    invalid["generators"][1]["energy_bid"][1]=NaN
    @test_throws ErrorException RM.R5MarketCase(invalid)
end

@testset "R5 market KKT ramp, integrity and statuses" begin
    d=deepcopy(hand_case().data)
    d["ies"]=Any[]
    d["T"]=2
    d["load_MW"]=[[20.0, 100.0]]
    d["reserve_up_MW"]=zeros(2)
    d["reserve_down_MW"]=zeros(2)
    g=deepcopy(d["generators"][1])
    merge!(
        g,
        Dict(
            "p_initial"=>20.0,
            "ramp_up_MW_h"=>20.0,
            "ramp_down_MW_h"=>20.0,
            "energy_bid"=>20.0,
            "up_bid"=>5.0,
            "down_bid"=>2.0,
        ),
    )
    expensive=deepcopy(g)
    merge!(
        expensive,
        Dict(
            "id"=>"G2",
            "energy_bid"=>50.0,
            "p_initial"=>0.0,
            "ramp_up_MW_h"=>200.0,
            "ramp_down_MW_h"=>200.0,
        ),
    )
    d["generators"]=[g, expensive]
    rampcase=RM.R5MarketCase(d)
    rr=RM.solve_r5_market(rampcase; optimizer = highs)
    @test rr["validation"]["optimality_pass"]
    @test rr["solver_objective"]≈4200 atol=1e-5
    @test rr["validation"]["LMP_USD_MWh"][1]≈[-10.0, 50.0] atol=1e-6
    @test rr["multipliers"]["ramp_up"][1][2]≈30.0 atol=1e-6
    for h in (1e-2, 1e-3, 1e-4)
        trial=deepcopy(rampcase.data)
        trial["load_MW"][1][1]+=h
        rt=RM.solve_r5_market(RM.R5MarketCase(trial); optimizer = highs)
        @test (rt["solver_objective"]-rr["solver_objective"])/h≈-10.0 rtol=1e-3
    end
    initial=deepcopy(rampcase.data)
    initial["T"]=1
    initial["load_MW"]=[[100.0]]
    initial["reserve_up_MW"]=[0.0]
    initial["reserve_down_MW"]=[0.0]
    for a in initial["generators"], k in ("energy_bid", "up_bid", "down_bid")
        a[k]=a[k][1]
    end
    initial["generators"][1]["p_initial"]=30.0
    ir=RM.solve_r5_market(RM.R5MarketCase(initial); optimizer = highs)
    @test ir["validation"]["optimality_pass"]
    @test ir["solver_objective"]≈3500 atol=1e-5
    capped=deepcopy(initial)
    capped["generators"][1]["p_bid_max"]=40.0
    cappedrun=RM.solve_r5_market(RM.R5MarketCase(capped); optimizer = highs)
    @test cappedrun["validation"]["optimality_pass"]
    @test cappedrun["values"]["P_G"][1][1]≈40.0 atol=1e-6
    @test cappedrun["solver_objective"]≈3800.0 atol=1e-5
    @test cappedrun["multipliers"]["pg_bid"][1][1]≈30.0 atol=1e-6
    for h in (1e-2, 1e-3, 1e-4)
        trial=deepcopy(initial)
        trial["generators"][1]["p_initial"]+=h
        rt=RM.solve_r5_market(RM.R5MarketCase(trial); optimizer = highs)
        @test (rt["solver_objective"]-ir["solver_objective"])/h≈-30.0 rtol=1e-3
    end
    r=RM.solve_r5_market(base; optimizer = highs)
    for key in ("multipliers", "raw_duals", "lower_bound_duals")
        bad=deepcopy(r)
        delete!(bad, key)
        @test RM.validate_r5_market(base, bad)["model_pass"]
        @test !RM.validate_r5_market(base, bad)["kkt_pass"]
    end
    invalid=deepcopy(base.data)
    delete!(invalid, "units")
    @test_throws ErrorException RM.R5MarketCase(invalid)
    invalid=deepcopy(base.data)
    invalid["generators"][1]["up_bid"][1]=-1
    @test_throws ErrorException RM.R5MarketCase(invalid)
    changed=RM.R5MarketCase(base.data)
    changed.data["load_MW"][1][1]+=1
    @test_throws ErrorException RM.build_r5_market(changed)
    quadratic=Model()
    @variable(quadratic, x>=0)
    @constraint(quadratic, x^2<=1)
    @objective(quadratic, Min, x)
    @test_throws ErrorException RM.r5_market_lp_types(quadratic)
    failed=RM.solve_r5_market(base; optimizer = ()->error("license unavailable fixture"))
    @test failed["status"]=="license_unavailable"
    @test !haskey(failed, "values")
    unsupported=RM.solve_r5_market(
        base;
        optimizer = ()->throw(MOI.UnsupportedAttribute(MOI.TimeLimitSec())),
    )
    @test unsupported["status"]=="unsupported_solver"
    dir=mktempdir(joinpath(root, "tmp"); cleanup = false)
    left=RM.save_r5_market_run(base, r, joinpath(dir, "left"))
    loaded=RM.read_r5_market_run(left)
    @test loaded.validation["optimality_pass"]
    @test loaded.case.sha256==base.sha256
    @test_throws ErrorException RM.save_r5_market_run(base, r, left)
    rightresult=RM.solve_r5_market(base; optimizer = clarabel)
    right=RM.save_r5_market_run(base, rightresult, joinpath(dir, "right"))
    @test RM.compare_r5_market_runs(left, right)["A2_pass"]
    failedpath=RM.save_r5_market_run(base, failed, joinpath(dir, "failed"))
    @test !RM.read_r5_market_run(failedpath).validation["model_pass"]
    @test !RM.compare_r5_market_runs(left, failedpath)["comparable"]
    wrong=deepcopy(r)
    wrong["source_hashes_at_solve"]["src/core/r5_market.jl"]="changed"
    @test_throws ErrorException RM.save_r5_market_run(base, wrong, joinpath(dir, "wrong"))
    wrong=deepcopy(r)
    wrong["validation"]["model_pass"]=false
    @test_throws ErrorException RM.save_r5_market_run(base, wrong, joinpath(dir, "wrong"))
    # 冻结源码在独立Julia进程重读，不能只依赖当前主包。
    replay=joinpath(left, "code", "replay.jl")
    replaytext=read(
        `$(Base.julia_cmd()) --startup-file=no --project=$(joinpath(left,"code")) $replay`,
        String,
    )
    @test occursin("frozen model=true kkt=true", replaytext)
    write(joinpath(left, "unexpected.txt"), "tamper")
    @test_throws ErrorException RM.read_r5_market_run(left)
    open(joinpath(right, "result.toml"), "a") do io
        write(io, "\n# modified after saving\n")
    end
    @test_throws ErrorException RM.read_r5_market_run(right)
end

@testset "R5 market independent dual evidence" begin
    r=RM.solve_r5_market(base; optimizer = highs)
    dual=RM.build_r5_market_dual(base; optimizer = clarabel)
    set_silent(dual.model)
    set_time_limit_sec(dual.model, 60.0)
    optimize!(dual.model)
    @test termination_status(dual.model)==MOI.OPTIMAL
    multipliers=Dict(
        string(k)=>(ndims(v)==1 ? collect(value.(v)) : RM.r5_market_rows(value.(v))) for
        (k, v) in dual.variables
    )
    trial=deepcopy(r)
    trial["multipliers"]=multipliers
    delete!(trial, "raw_duals")
    delete!(trial, "lower_bound_duals")
    check=RM.validate_r5_market(base, trial)
    @test all(x["pass"] for x in check["rows"])
    r["independent_dual"]=Dict(
        "status"=>"OPTIMAL",
        "verified"=>true,
        "objective"=>objective_value(dual.model),
        "multipliers"=>multipliers,
        "dual_value_recomputed"=>check["dual_value"],
        "relative_gap"=>check["relative_gap"],
    )
    @test RM.r5_market_check_independent_dual(base, r)===nothing
    dir=mktempdir(joinpath(root, "tmp"); cleanup = false)
    saved=RM.save_r5_market_run(base, r, joinpath(dir, "independent"))
    @test RM.read_r5_market_run(saved).result["independent_dual"]["verified"]
    wrong=deepcopy(r)
    wrong["independent_dual"]["objective"]+=1.0
    @test_throws ErrorException RM.r5_market_check_independent_dual(base, wrong)
    wrong=deepcopy(r)
    wrong["independent_dual"]["multipliers"]["energy"][1]+=1.0
    @test_throws ErrorException RM.r5_market_check_independent_dual(base, wrong)
    wrong=deepcopy(r)
    delete!(wrong["independent_dual"], "multipliers")
    @test_throws ErrorException RM.r5_market_check_independent_dual(base, wrong)
end

end
