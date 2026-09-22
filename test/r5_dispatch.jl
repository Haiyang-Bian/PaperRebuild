module R5DispatchTests
using PaperRebuild, Test, JuMP, HiGHS, Clarabel, TOML
const RD=PaperRebuild
include(joinpath(@__DIR__, "..", "scripts", "r5_dispatch_cases.jl"))
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

@testset "R5 building total heat and units" begin
    k=r5_building_coefficients(0.02, 0.004, 0.25)
    @test k.η_H==12.5
    @test k.U==0.05
    @test r5_building_temperature(293.15, 0.04, 0.0, 283.15, 0.02, 0.004, 1.0)≈293.15
    @test r5_building_temperature(293.15, 0.02, 0.02, 283.15, 0.02, 0.004, 1.0)≈293.15
    @test r5_building_temperature(293.15, 0.0, 0.04, 283.15, 0.02, 0.004, 1.0)≈293.15
    @test r5_building_temperature(293.15, 0.02, 0.0, 280.0, 0.02, 0.0, 0.25)≈293.40
    @test r5_building_temperature(293.15, 0.0, 0.0, 283.15, 0.02, 0.004, 1.0)<293.15
    for args in ((0.0, 0.1, 1.0), (1.0, -0.1, 1.0), (1.0, 0.1, 0.0), (Inf, 0.1, 1.0))
        @test_throws ArgumentError r5_building_coefficients(args...)
    end
    @test_throws ArgumentError r5_building_temperature(293.15, -1, 0, 283.15, 1, 0, 1)
end

@testset "R5 deterministic dispatch hand and reserve signs" begin
    for optimizer in (highs, clarabel)
        c=R5DispatchCase(r5_dispatch_hand())
        built=build_r5_dispatch(c)
        @test built.model_type=="continuous_LP"
        @test JuMP.termination_status(built.model)==JuMP.MOI.OPTIMIZE_NOT_CALLED
        r=solve_r5_dispatch(c; optimizer)
        println(get(r, "error", "dispatch: "*r["status"]))
        @test r["validation"]["model_pass"]
        @test r["cost_optimization_complete"]
        @test r["validation"]["operating_net_cost"]≈14.2 atol=1e-5
        @test r["values"]["P_DER"][1][1]≈0.042 atol=1e-7
        @test r["values"]["P_PCC"][1][1]≈0.142 atol=1e-7
        @test r["values"]["v"][2][1]≈1-(0.01*0.142+0.005*0.02) atol=1e-7
        @test haskey(r, "raw_constraint_duals")
        cq=R5DispatchCase(r5_dispatch_hand(; dt = 0.25))
        rq=solve_r5_dispatch(cq; optimizer)
        @test rq["validation"]["model_pass"]
        @test rq["validation"]["operating_net_cost"]≈14.2/4 atol=1e-5
        for (side, pda, expected) in (("up", 0.162, 14.1), ("down", 0.122, 14.16))
            d=r5_dispatch_hand()
            d["award"]["P_DA_MW"]=[pda]
            d["award"]["R_$(side)_MW"]=[0.02]
            d["realtime"]["alpha_$side"]=[1.0]
            rr=solve_r5_dispatch(R5DispatchCase(d); optimizer)
            @test rr["validation"]["model_pass"]
            @test rr["validation"]["mismatch_MWh"]<=1e-6
            @test rr["validation"]["operating_net_cost"]≈expected atol=1e-5
            @test rr["validation"]["delivered_MW"][1]≈(side=="up" ? 0.02 : -0.02) atol=1e-7
        end
        d=r5_dispatch_hand()
        d["devices"][1]["p_max_MW"]=0.0
        d["buildings"][1]["P_DH_max_MW"]=0.1
        d["heat"]["sources"][1]["T_min_K"]=320.15
        d["heat"]["sources"][1]["T_max_K"]=320.15
        d["heat"]["pipes"][1]["history_S_K"]=[320.15]
        localheat=solve_r5_dispatch(R5DispatchCase(d); optimizer)
        @test localheat["validation"]["model_pass"]
        @test localheat["values"]["P_DH"][1][1]≈0.042 atol=1e-7
        @test localheat["values"]["H_D"][1][1]≈0.0 atol=1e-7
        @test localheat["validation"]["operating_net_cost"]≈14.2 atol=1e-5
    end
end

@testset "R5 transport, mixing and delivery failure" begin
    d=r5_dispatch_hand()
    h=d["heat"]
    p=h["pipes"][1]
    for length in (180.0, 360.0, 540.0), loss in (0.0, 0.1)
        pp=deepcopy(p)
        pp["length_m"]=length
        pp["loss_W_mK"]=loss
        pp["history_S_K"]=[310.0, 320.0]
        pp["history_R_K"]=[300.0, 310.0]
        k=fixed_flow_kernel(1, 1000, 0.01, length, 1, loss)
        expected=pipe_outlet([330.0, 340.0], [310.0, 320.0], k, 280.0)
        for t in 1:2
            replay=RD.r5_dispatch_pipe_replay(pp, h, 1, t, [330.0, 340.0], 280.0, "S")
            @test replay.temperature≈expected[t] atol=1e-10
            @test replay.weight_sum≈1 atol=1e-12
        end
    end
    d=r5_dispatch_hand()
    pipes=d["heat"]["pipes"]
    push!(pipes, deepcopy(pipes[1]))
    pipes[2]["id"]="parallel"
    for (i, p) in enumerate(pipes)
        p["m_kg_s"]=0.5
        p["history_S_K"]=fill(i==1 ? 340.15 : 320.15, 2)
        p["history_R_K"]=fill(320.15, 2)
    end
    r=solve_r5_dispatch(R5DispatchCase(d); optimizer = highs)
    @test r["validation"]["model_pass"]
    @test r["values"]["τ_S"][2][1]≈330.15
    d=r5_dispatch_hand()
    d["award"]["R_up_MW"]=[0.1]
    d["realtime"]["alpha_up"]=[1.0]
    fail=solve_r5_dispatch(R5DispatchCase(d); optimizer = highs)
    @test fail["status"]=="solver_infeasible"
    @test !haskey(fail, "values")
    @test !fail["validation"]["model_pass"]
    d["realtime"]["delta"]=1.0
    r=solve_r5_dispatch(R5DispatchCase(d); optimizer = highs)
    @test r["validation"]["model_pass"]
    @test r["validation"]["mismatch_MWh"]≈0.1
    d["realtime"]["delta"]=0.1
    d["realtime"]["alpha_up"]=[0.1]
    r=solve_r5_dispatch(R5DispatchCase(d); optimizer = highs)
    @test r["validation"]["model_pass"]
    @test r["validation"]["mismatch_MWh"]≈0.01
end

@testset "R5 input, independent residual and immutable runs" begin
    integer_data=r5_dispatch_hand()
    float_data=deepcopy(integer_data)
    float_data["devices"][1]["node"]=2.0
    float_data["heat"]["sources"][1]["node"]=1.0
    float_data["heat"]["pipes"][1]["from"]=1.0
    float_data["electric"]["lines"][1]["to"]=2.0
    float_data["buildings"][1]["heat_node"]=2.0
    @test R5DispatchCase(integer_data).sha256==R5DispatchCase(float_data).sha256
    @test build_r5_dispatch(R5DispatchCase(float_data)).model_type=="continuous_LP"
    for mutate in (
        d->(d["heat"]["pipes"][1]["history_S_K"]=Float64[]),
        d->(d["heat"]["pipes"][1]["m_kg_s"]=0.0),
        d->(d["heat"]["sources"][1]["m_kg_s"]=2.0),
        d->(d["buildings"][1]["C_MWh_K"]=-1.0),
        d->(d["units"]["power"]="kW"),
        d->(d["realtime"]["penalty_USD_MWh"]=0.0),
        d->(d["electric"]["lines"][1]["to"]=1),
        d->(d["buildings"][1]["terminal_rule"]="implicit"),
    )
        d=r5_dispatch_hand()
        mutate(d)
        @test_throws Exception R5DispatchCase(d)
    end
    c=R5DispatchCase(r5_dispatch_hand())
    r=solve_r5_dispatch(c; optimizer = highs)
    for (name, group) in (
        ("P_DER", "linear_electric_pass"),
        ("τ_pipe_R", "fixed_flow_heat_pass"),
        ("τ_IN", "comfort_pass"),
        ("delivery", "delivery_pass"),
    )
        broken=deepcopy(r)
        broken["values"][name][1][1]+=0.02
        @test !validate_r5_dispatch(c, broken)[group]
    end
    broken=deepcopy(r)
    delete!(broken, "solver_objective_bound")
    @test !validate_r5_dispatch(c, broken)["optimality_pass"]
    exhausted=solve_r5_dispatch(c; optimizer = highs, budget_sec = 1e-12)
    @test exhausted["status"]=="budget_exhausted_before_solve"
    @test !haskey(exhausted, "values")
    license=solve_r5_dispatch(c; optimizer = ()->error("license unavailable"))
    @test license["status"]=="license_unavailable"
    @test !license["cost_optimization_complete"]
    mktempdir() do tmp
        dir=joinpath(tmp, "saved")
        save_r5_dispatch_run(c, r, dir)
        x=read_r5_dispatch_run(dir)
        @test x.case.sha256==c.sha256
        @test x.validation["model_pass"]
        @test_throws Exception save_r5_dispatch_run(c, r, dir)
        open(joinpath(dir, "case.toml"), "a") do io
            write(io, "\n# changed\n")
        end
        @test_throws Exception read_r5_dispatch_run(dir)
        dir2=joinpath(tmp, "failure")
        save_r5_dispatch_run(c, exhausted, dir2)
        @test read_r5_dispatch_run(dir2).result["status"]=="budget_exhausted_before_solve"
    end
    c.data["dt_h"]=2.0
    @test_throws Exception build_r5_dispatch(c)
end

@testset "R5 verified market award bridge" begin
    root=normpath(joinpath(@__DIR__, ".."))
    c=load_r5_market_case(joinpath(root, "configs", "r5", "market", "hand_hour.toml"))
    r=solve_r5_market(c; optimizer = highs)
    dual=build_r5_market_dual(c; optimizer = highs)
    set_silent(dual.model)
    optimize!(dual.model)
    multipliers=Dict(
        string(k)=>(ndims(x)==1 ? collect(value.(x)) : RD.r5_market_rows(value.(x))) for
        (k, x) in dual.variables
    )
    trial=deepcopy(r)
    trial["multipliers"]=multipliers
    delete!(trial, "raw_duals")
    delete!(trial, "lower_bound_duals")
    check=validate_r5_market(c, trial)
    @test all(x["pass"] for x in check["rows"])
    r["independent_dual"]=Dict(
        "status"=>"OPTIMAL",
        "multipliers"=>multipliers,
        "verified"=>true,
        "objective"=>objective_value(dual.model),
        "dual_value_recomputed"=>check["dual_value"],
        "relative_gap"=>check["relative_gap"],
    )
    mktempdir() do tmp
        dir=joinpath(tmp, "market")
        save_r5_market_run(c, r, dir)
        award=r5_award_from_market(dir, c.data["ies"][1]["id"])
        @test award["P_DA_MW"]≈r["values"]["P_IES"][1]
        @test award["energy_price"]≈[20.0]
        @test award["parent_case_sha256"]==c.sha256
        @test award["dt_h"]==1.0
        @test_throws Exception r5_award_from_market(dir, "missing")
        d=r5_dispatch_hand()
        d["award"]=award
        d["electric"]["pcc_max_MW"]=100.0
        @test R5DispatchCase(d).data["award"]["parent_run_id"]==r["run_id"]
        d["dt_h"]=0.25
        @test_throws Exception R5DispatchCase(d)
        dir2=joinpath(tmp, "uncertified")
        delete!(r, "independent_dual")
        save_r5_market_run(c, r, dir2)
        @test_throws Exception r5_award_from_market(dir2, c.data["ies"][1]["id"])
    end
end
end
