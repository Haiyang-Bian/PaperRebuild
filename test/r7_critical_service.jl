module R7CriticalServiceTests
using PaperRebuild, Test, TOML, JuMP, HiGHS
const PR=PaperRebuild
const ROOT=normpath(joinpath(@__DIR__, ".."))
const OPT=optimizer_with_attributes(
    HiGHS.Optimizer,
    "threads"=>1,
    "primal_feasibility_tolerance"=>1e-9,
    "dual_feasibility_tolerance"=>1e-9,
    "mip_feasibility_tolerance"=>1e-9,
    "mip_rel_gap"=>1e-9,
)

@testset "R9-RL1 and R9-RL2 important load is a subset of full physical demand" begin
    old=load_r7_recovery_case(joinpath(ROOT, "configs/r7/recovery-hand.toml"))
    original=deepcopy(old.data)
    c=with_r7_critical_load(
        old,
        [0.0; 0.3;;];
        provenance = "synthetic hand split 0.3 important plus 0.3 ordinary MW",
    )
    @test old.data==original && old.sha256!=c.sha256
    @test c.data["electric"]==old.data["electric"] && c.data["heat"]==old.data["heat"]
    @test c.data["devices"]==old.data["devices"]
    r=solve_r7_recovery(c, [1]; optimizer = OPT, budget_sec = 60)
    @test r["candidate_accepted"] && r["loss_optimization_complete"]
    @test r["objective_kind"]=="expected_critical_electric_unserved_energy_MWh"
    q=r["validation"]
    # 故障后负荷岛只有0.2 MWh电池：0.3关键需求中至少损失0.1 MWh。
    @test q["loss_critical_electric_MWh"]≈0.1 atol=1e-7
    @test q["loss_ordinary_electric_MWh"]≈0.3 atol=1e-7
    @test q["loss_electric_MWh"]≈0.4 atol=1e-7
    @test q["loss_MWh"]==q["loss_critical_electric_MWh"]
    @test q["loss_all_energy_MWh"]≈q["loss_electric_MWh"]+q["loss_heat_MWh"] atol=1e-8
    @test q["loss_heat_MWh"]>0.1
    @test q["service_objective"]=="critical_electric_v1"
    @test r7_recovery_loss_cap(c).feasible_upper_MWh≈0.3
    dual=build_r7_recourse_dual(r7_recovery_lp(c, [0]), [1]; optimizer = OPT)
    set_silent(dual.model)
    optimize!(dual.model)
    @test termination_status(dual.model)==MOI.OPTIMAL
    dq=validate_r7_dual(dual.lp, [1], value.(dual.lambda))
    @test dq["dual_feasible"]
    @test dq["dual_objective_MWh"]≈0.1 atol=1e-7
    adv=solve_r7_adversary(c; optimizer = OPT, budget_sec = 0)
    @test adv["objective_kind"]=="worst_expected_critical_electric_unserved_energy_MWh"
    @test adv["validation"]["threshold_status"]=="unresolved"
    legacy=solve_r7_recovery(old, [1]; optimizer = OPT, budget_sec = 60)
    @test legacy["solver_objective_MWh"]≈17/30 atol=1e-7
    @test legacy["objective_kind"]=="expected_unserved_energy_MWh"
    @test !haskey(legacy["values"], "P_shed_critical")
    @test !haskey(legacy["validation"], "service_objective")
    for (dt, expected) in ((0.5, 0.05), (2.0, 0.4))
        d=deepcopy(c.data)
        d["dt_h"]=dt
        rr=solve_r7_recovery(R7RecoveryCase(d), [1]; optimizer = OPT, budget_sec = 60)
        @test rr["candidate_accepted"] && rr["loss_optimization_complete"]
        @test rr["solver_objective_MWh"]≈expected atol=1e-7
    end
    for mutate in (
        d->(d["load_service"]["critical_load_MW"]=[[0.0], [0.7]]),
        d->(d["load_service"]["critical_load_MW"]=[[0.0], [-0.1]]),
        d->(d["load_service"]["critical_load_MW"]=[[0.0], [NaN]]),
        d->(d["load_service"]["critical_load_MW"]=[[0.0, 0.1], [0.3, 0.3]]),
        d->(d["load_service"]["heat_rule"]="silently_drop_heat"),
        d->(d["load_service"]["power_factor_rule"]="different_unprovided_power_factor"),
        d->(d["load_service"]["provenance"]=""),
    )
        d=deepcopy(c.data)
        mutate(d)
        @test_throws ErrorException R7RecoveryCase(d)
    end
    bad=deepcopy(r)
    a=PR.r7_unpack(bad["values"], "P_shed_critical")
    b=PR.r7_unpack(bad["values"], "P_shed_ordinary")
    b .+= a
    a .= 0
    bad["values"]["P_shed_critical"]=PR.r7_pack(a)
    bad["values"]["P_shed_ordinary"]=PR.r7_pack(b)
    bad["solver_objective_MWh"]=0.0
    @test !validate_r7_recovery(c, bad)["model_pass"]
    bad=deepcopy(r)
    bad["objective_kind"]="expected_unserved_energy_MWh"
    @test_throws ErrorException validate_r7_recovery(c, bad)
    zero=with_r7_critical_load(
        old,
        zeros(2, 1);
        provenance = "synthetic zero important demand boundary",
    )
    rz=solve_r7_recovery(zero, [1]; optimizer = OPT, budget_sec = 60)
    @test rz["candidate_accepted"] && abs(rz["solver_objective_MWh"])<1e-8
    @test rz["validation"]["loss_all_energy_MWh"]>0
    @test solve_r7_recovery(c, [1]; optimizer = OPT, budget_sec = 0)["status"]=="budget_exhausted"
    # 两个场景继承不同电池库存，概率加权关键失供为0.25×0.3+0.75×0.1。
    d=deepcopy(c.data)
    d["probabilities"]=[0.25, 0.75]
    d["devices"][1]["previous_P_MW"]=[0.5, 0.5]
    d["devices"][2]["initial_MWh"]=[0.0, 0.2]
    d["heat"]["pipes"][1]["initial_S_K"]=[343.15, 343.15]
    d["heat"]["pipes"][1]["initial_R_K"]=[313.15, 313.15]
    weighted=solve_r7_recovery(R7RecoveryCase(d), [1]; optimizer = OPT, budget_sec = 60)
    @test weighted["candidate_accepted"] && weighted["loss_optimization_complete"]
    @test weighted["validation"]["loss_critical_electric_MWh"]≈0.15 atol=1e-7
    @test vec(PR.r7_unpack(weighted["values"], "P_shed_critical")[2, 1, :])≈[0.3, 0.1] atol=1e-7
    archive=mktempdir(joinpath(ROOT, "tmp"); cleanup = false)
    save_r7_recovery(c, r, joinpath(archive, "critical"))
    @test read_r7_recovery(joinpath(archive, "critical")).validation["loss_MWh"]≈0.1 atol=1e-7
    moved=joinpath(archive, "relocated")
    cp(joinpath(archive, "critical"), moved)
    replay=joinpath(moved, "code", "replay.jl")
    project="--project="*ROOT
    output=read(`$(Base.julia_cmd()) --startup-file=no $project $replay`, String)
    @test occursin("model=true", output)
    open(joinpath(moved, "result.toml"), "a") do io
        write(io, "\n# deliberate tamper fixture\n")
    end
    @test_throws ErrorException read_r7_recovery(moved)
    println("Critical service evidence preserved: ", relpath(archive, ROOT))
end

include("r7_flow_planning_fixtures.jl")
@testset "R9-RL3 critical metric follows inherited state and all planning objectives" begin
    old, flow=joint_test_case(; limit = 0.1, battery_rule = "per_period_exclusive_v1")
    normal=with_r7_critical_load(
        old.normal,
        [0.0 0 0 0; 0.2 0.3 0.5 0.4];
        provenance = "synthetic nonconstant critical demand; full original electric and heat demands preserved",
    )
    c=R7PlanningCase(normal, old.specification)
    flow["case_sha256"]=c.sha256
    flow["normal_flow"]["case_sha256"]=normal.sha256
    @test normal.data["electric"]==old.normal.data["electric"]
    @test PR.r8_loss_caps(c)≈[0.3, 0.5]
    @test PR.r7_event_template(c, 1).data["load_service"]["critical_load_MW"]==[[0.0], [0.3]]
    n=solve_r7_normal_flow(normal, flow["normal_flow"]; optimizer = OPT, budget_sec = 60)
    @test n["candidate_accepted"]
    ev=PR.r7_joint_event_values(c, n, 2)
    @test ev.case.data["load_service"]["critical_load_MW"]==[[0.0], [0.5]]
    archive=mktempdir(joinpath(ROOT, "tmp"); cleanup = false)
    for method in (:extensive, :finite_fault_ccg)
        r=solve_r7_planning(c; optimizer = OPT, method, budget_sec = 60)
        @test r["validation"]["robust_model_pass"]
        path=joinpath(archive, "planning-"*string(method))
        save_r7_planning(c, r, path)
        @test read_r7_planning(path).validation["robust_model_pass"]
    end
    flows=Dict(
        PR.r7_planning_pair_key(pair)=>Dict(
            "m_pipe"=>PR.r7_joint_bounds(flow, pair)["pipe_min"],
            "m_source"=>PR.r7_joint_bounds(flow, pair)["source_min"],
            "m_load"=>PR.r7_joint_bounds(flow, pair)["load_min"],
        ) for pair in PR.r7_planning_pairs(c)
    )
    linked=r7_linked_planning_spec(c; flows, substeps = 1)
    lr=solve_r7_linked_planning(c, linked; optimizer = OPT, method = :extensive, budget_sec = 60)
    @test lr["validation"]["robust_model_pass"]
    jr=solve_r7_flow_planning(c, flow; optimizer = OPT, budget_sec = 60)
    @test jr["candidate_accepted"]
    for energy in (false, true), mode in (:economic, :threshold, :penalty)
        s=energy ? r8_energy_spec(c; pipe_capacity_MW = [1.05], loss_rule = :lossless, mode) :
          r8_spec(c, flow; mode)
        @test s["service_objective"]=="critical_electric_v1"
        r=energy ? solve_r8_energy_case(c, s; optimizer = OPT, budget_sec = 60) :
          solve_r8_case(c, flow, s; optimizer = OPT, budget_sec = 60)
        @test r["validation"]["primary_model_pass"] && r["validation"]["recovery_verified"]
        @test r["evaluation"]["objective_kind"]=="sum_event_worst_expected_critical_electric_unserved_energy_MWh"
        p=r["primary"]
        expected=p["validation"]["normal_cost_USD"]+(mode==:penalty ? 500sum(p["eta_MWh"]) : 0.0)
        @test p["solver_objective"]≈expected atol=1e-5
        mode==:penalty &&
            @test p["objective_kind"]=="normal_cost_plus_event_critical_electric_unserved_penalty_USD"
        for w in r["evaluation"]["validation"]["witness_checks"]
            q=w["shared"]
            @test q["loss_MWh"]==q["loss_critical_electric_MWh"]
            @test q["loss_all_energy_MWh"]≈q["loss_electric_MWh"]+q["loss_heat_MWh"] atol=1e-8
            @test q["loss_electric_MWh"]≈q["loss_critical_electric_MWh"]+q["loss_ordinary_electric_MWh"] atol=1e-7
        end
        path=joinpath(archive, "r8-"*string(energy)*"-"*string(mode))
        if energy
            save_r8_energy_run(c, s, r, path)
            @test read_r8_energy_run(path).validation["primary_model_pass"]
        else
            save_r8_run(c, flow, s, r, path)
            @test read_r8_run(path).validation["primary_model_pass"]
        end
        bad=deepcopy(s)
        delete!(bad, "service_objective")
        @test_throws ErrorException (
            energy ? build_r8_energy_model(c, bad) : build_r8_model(c, flow, bad)
        )
    end
    println("Critical planning evidence preserved: ", relpath(archive, ROOT))
end

@testset "R9-RL3 CNY penalty applies only to critical energy" begin
    old, flow=joint_test_case(; limit = 0.1, battery_rule = "per_period_exclusive_v1")
    d=deepcopy(old.normal.data)
    d["schema"]="r7-normal-case-v2"
    d["currency"]="CNY"
    d["units"]["price"]="CNY/MWh"
    d["electric"]["price_MWh"]=pop!(d["electric"], "price_USD_MWh")
    for g in d["devices"]
        g["cost_P_MWh"]=pop!(g, "cost_P_USD_MWh")
        g["kind"]=="CHP" && (g["startup_cost"]=pop!(g, "startup_cost_USD"))
    end
    normal=with_r7_critical_load(
        R7NormalCase(d),
        [0.0 0 0 0; 0.2 0.3 0.5 0.4];
        provenance = "synthetic CNY and critical-load joint interface verification",
    )
    c=R7PlanningCase(normal, old.specification)
    flow["case_sha256"]=c.sha256
    flow["normal_flow"]["case_sha256"]=normal.sha256
    archive=mktempdir(joinpath(ROOT, "tmp"); cleanup = false)
    for energy in (false, true)
        s=energy ?
          r8_energy_spec(
            c;
            pipe_capacity_MW = [1.05],
            loss_rule = :lossless,
            mode = :penalty,
            penalty_MWh = 10000.0,
        ) : r8_spec(c, flow; mode = :penalty, penalty_MWh = 10000.0)
        r=energy ? solve_r8_energy_case(c, s; optimizer = OPT, budget_sec = 60) :
          solve_r8_case(c, flow, s; optimizer = OPT, budget_sec = 60)
        @test r["validation"]["primary_model_pass"] && r["validation"]["recovery_verified"]
        @test r["currency"]=="CNY"
        p=r["primary"]
        @test p["objective_kind"]=="normal_cost_plus_event_critical_electric_unserved_penalty_CNY"
        @test p["solver_objective"]≈p["validation"]["normal_cost"]+10000sum(p["eta_MWh"]) atol=1e-5
        @test r["evaluation"]["objective_kind"]=="sum_event_worst_expected_critical_electric_unserved_energy_MWh"
        @test all(
            w["shared"]["loss_MWh"]==w["shared"]["loss_critical_electric_MWh"] for
            w in r["evaluation"]["validation"]["witness_checks"]
        )
        path=joinpath(archive, "CNY-critical-"*string(energy))
        if energy
            save_r8_energy_run(c, s, r, path)
            q=read_r8_energy_run(path)
        else
            save_r8_run(c, flow, s, r, path)
            q=read_r8_run(path)
        end
        @test q.validation["primary_model_pass"] && q.result["currency"]=="CNY"
    end
    println("CNY critical evidence preserved: ", relpath(archive, ROOT))
end
end
