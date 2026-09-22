module R7EnergizationTests
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

function hand(; demand = 0.6, critical = 0.3, battery = false)
    d=TOML.parsefile(joinpath(ROOT, "configs/r7/recovery-hand.toml"))
    battery || filter!(g->g["kind"]!="BES", d["devices"])
    d["electric"]["root_eligible"]=[1, battery ? 1 : 0]
    d["electric"]["load_MW"]=[[0.0], [demand]]
    d["heat"]["load_MW"]=[[0.0], [0.0]]
    # 合成电网域解析例：降低热电比以容纳健康线路下的发热；不修改已有案例文件。
    d["devices"][1]["heat_ratio"]=0.1
    old=with_r7_critical_load(
        R7RecoveryCase(d),
        [0.0; critical;;];
        provenance = "synthetic electric energization hand case",
    )
    c=with_r7_electric_domain(
        old,
        "partial_energization_v1";
        provenance = "R9-RE1:RE4 explicit blackout adoption",
    )
    old, c
end

function solved(c, fault; kwargs...)
    r=solve_r7_recovery(c, fault; optimizer = OPT, budget_sec = 60, kwargs...)
    @test r["candidate_accepted"]
    @test r["loss_optimization_complete"]
    r
end

@testset "R9-RE1 R9-RE2 R9-RE3 R9-RE4 blackout, electrical gating and inherited commitment" begin
    old, c=hand(; demand = 0.0, critical = 0.0)
    @test !haskey(old.data["electric"], "recovery_domain")
    @test old.sha256!=c.sha256
    legacy=solve_r7_recovery(old, [1]; optimizer = OPT, budget_sec = 60)
    @test legacy["status"]=="infeasible_certified"
    r0=solved(c, [1])
    @test r0["solver_objective_MWh"]≈0 atol=1e-8
    @test vec(PR.r7_unpack(r0["values"], "energized"))≈[1, 0] atol=1e-8
    @test PR.r7_unpack(r0["values"], "v")[2, 1, 1]≈0 atol=1e-8
    old, c=hand()
    r=solved(c, [1])
    @test r["validation"]["loss_critical_electric_MWh"]≈0.3 atol=1e-7
    @test r["validation"]["loss_electric_MWh"]≈0.6 atol=1e-7
    @test sum(PR.r7_unpack(r["values"], "a_on"))+sum(PR.r7_unpack(r["values"], "a_off"))≈0 atol=1e-8
    for (dt, want) in ((0.25, 0.075), (2.0, 0.6))
        d=deepcopy(c.data)
        d["dt_h"]=dt
        if dt==0.25
            # 先保留父状态：0.5 MW以1 MW/h只能降到0.25 MW，孤立无负荷源确实不可行。
            @test solve_r7_recovery(R7RecoveryCase(d), [1]; optimizer = OPT, budget_sec = 60)["status"]=="infeasible_certified"
            d["devices"][1]["previous_P_MW"]=[0.0]
            d["preplan_id"]="synthetic-zero-prior-power-quarter-hour-integral-test"
        end
        rd=solved(R7RecoveryCase(d), [1])
        @test rd["solver_objective_MWh"]≈want atol=1e-7
    end
    healthy=solved(c, [0])
    @test healthy["solver_objective_MWh"]≈0 atol=1e-7
    @test vec(PR.r7_unpack(healthy["values"], "energized"))≈[1, 1] atol=1e-8
    for (key, i, value) in
        (("energized", 2, 1.0), ("v", 2, 0.95), ("live", 1, 1.0), ("P_shed", 2, 0.3))
        bad=deepcopy(r)
        a=PR.r7_unpack(bad["values"], key)
        a[i]=value
        bad["values"][key]=PR.r7_pack(a)
        @test !validate_r7_recovery(c, bad)["model_pass"]
    end
    d=deepcopy(c.data)
    d["electric"]["shed_fraction_max"][2]=0.5
    @test solve_r7_recovery(R7RecoveryCase(d), [1]; optimizer = OPT, budget_sec = 60)["status"]=="infeasible_certified"
    # 不能用停电取消已开CHP的最小出力或首步爬坡约束。
    for change in (:minimum, :ramp)
        d=deepcopy(c.data)
        change==:minimum ? (d["devices"][1]["P_min_MW"]=0.2) : (d["devices"][1]["ramp_MW_h"]=0.1)
        @test solve_r7_recovery(R7RecoveryCase(d), [1]; optimizer = OPT, budget_sec = 60)["status"]=="infeasible_certified"
    end
    # 未开CHP不能凭名牌容量充当根；PV不是声明的成网源。
    d=deepcopy(c.data)
    d["devices"][1]["commitment"]=[0]
    d["devices"][1]["previous_commitment"]=0
    d["devices"][1]["previous_P_MW"]=[0.0]
    off=solved(R7RecoveryCase(d), [0])
    @test all(abs.(PR.r7_unpack(off["values"], "energized")) .< 1e-8)
    @test off["solver_objective_MWh"]≈0.3 atol=1e-8
    d=deepcopy(c.data)
    push!(
        d["devices"],
        Dict(
            "id"=>"PV2",
            "kind"=>"PV",
            "electric_node"=>2,
            "P_max_MW"=>1.0,
            "available_MW"=>[[1.0]],
        ),
    )
    push!(
        d["devices"],
        Dict(
            "id"=>"EB2",
            "kind"=>"EB",
            "electric_node"=>2,
            "heat_node"=>2,
            "P_max_MW"=>0.1,
            "heat_ratio"=>1.0,
        ),
    )
    pv=solved(R7RecoveryCase(d), [1])
    @test pv["solver_objective_MWh"]≈0.3 atol=1e-8
    @test all(abs.(PR.r7_unpack(pv["values"], "P")[2:3, :, :]) .< 1e-8)
    _, bat=hand(; battery = true)
    rb=solved(bat, [1])
    @test rb["solver_objective_MWh"]≈0.1 atol=1e-7
    d=deepcopy(bat.data)
    d["electric"]["root_eligible"][2]=0
    no_root=solved(R7RecoveryCase(d), [1])
    @test no_root["solver_objective_MWh"]≈0.3 atol=1e-7
    @test all(abs.(PR.r7_unpack(no_root["values"], "P_dis")) .< 1e-8)
    @test PR.r7_unpack(no_root["values"], "E_BES")[2, 2, 1]≈0.2 atol=1e-8

    # 停电分量内部机械开关仍闭合：不应平白收取断开动作，死网闭环也不是带电环路。
    d=deepcopy(c.data)
    e=d["electric"]
    e["nodes"]=4
    e["root_eligible"]=[1, 0, 0, 0]
    e["load_MW"]=[[0.0], [0.6], [0.0], [0.0]]
    e["tan_phi"]=zeros(4)
    e["shed_fraction_max"]=ones(4)
    e["switch_budget"]=0
    for (i, j) in ((2, 3), (3, 4), (4, 2))
        line=deepcopy(e["lines"][1])
        line["from"]=i
        line["to"]=j
        line["vulnerable"]=false
        push!(e["lines"], line)
    end
    d["load_service"]["critical_load_MW"]=[[0.0], [0.3], [0.0], [0.0]]
    dead=R7RecoveryCase(d)
    rd=solved(dead, [1, 0, 0, 0])
    @test vec(PR.r7_unpack(rd["values"], "z"))≈[0, 1, 1, 1] atol=1e-8
    @test vec(PR.r7_unpack(rd["values"], "energized"))≈[1, 0, 0, 0] atol=1e-8
    @test all(abs.(PR.r7_unpack(rd["values"], "live")) .< 1e-8)
    @test sum(PR.r7_unpack(rd["values"], "a_off"))≈0 atol=1e-8
    @test_throws ErrorException build_r7_recovery(
        dead,
        [1, 0, 0, 0];
        fixed_z = [0, 1, 1, 1],
        fixed_energized = ones(Int, 4),
    )

    # 固定机械开关仍有带电选择；同时固定带电模式后才允许抽取真实LP对偶。
    @test build_r7_recovery(c, [1]; fixed_z = [0]).model_class=="MILP"
    @test build_r7_recovery(c, [1]; fixed_z = [0], fixed_energized = [1, 0]).model_class=="LP"
    mode=Dict("switch"=>[0], "energized"=>[1, 0])
    fixed=solved(c, [1]; fixed_z = [0], fixed_energized = [1, 0])
    lp=r7_recovery_lp(c, mode)
    dual=build_r7_recourse_dual(lp, [1]; optimizer = OPT)
    set_silent(dual.model)
    optimize!(dual.model)
    @test termination_status(dual.model)==MOI.OPTIMAL
    q=validate_r7_dual(lp, [1], value.(dual.lambda))
    @test q["dual_feasible"]
    @test q["dual_objective_MWh"]≈fixed["solver_objective_MWh"] atol=1e-7
    @test_throws ErrorException r7_recovery_lp(c, [0])
    @test_throws ErrorException build_r7_recovery(c, [1]; fault_variables = true, fixed_z = [0])
    @test_throws ErrorException build_r7_recovery(old, [1]; fixed_z = [0], fixed_energized = [1, 0])
    @test_throws ErrorException build_r7_recovery(c, [1]; fixed_z = [0], fixed_energized = [1, 0.5])
    @test_throws ErrorException with_r7_electric_domain(c, "unknown"; provenance = "test")
    @test_throws ErrorException with_r7_electric_domain(
        c,
        "partial_energization_v1";
        provenance = "",
    )
    enumerated=enumerate_r7_recovery(c, [1]; optimizer = OPT, budget_sec = 60)
    @test enumerated["gap_certified"]
    @test enumerated["upper_bound_MWh"]≈0.3 atol=1e-7
    audit=audit_r7_faults(c; optimizer = OPT, budget_sec = 60)
    @test audit["all_faults_attempted"]
    @test audit["upper_bound_MWh"]≈0.3 atol=1e-7
    @test solve_r7_recovery(c, [1]; optimizer = OPT, budget_sec = 0)["status"]=="budget_exhausted"
    folder=mktempdir(joinpath(ROOT, "tmp"); cleanup = false)
    for (name, input, result) in (
        ("zero", hand(; demand = 0.0, critical = 0.0)[2], r0),
        ("critical", c, r),
        ("fixed", c, fixed),
        ("dead-cycle", dead, rd),
    )
        save_r7_recovery(input, result, joinpath(folder, name))
        @test read_r7_recovery(joinpath(folder, name)).validation["model_pass"]
    end
    relocated=joinpath(folder, "relocated")
    cp(joinpath(folder, "fixed"), relocated)
    replay=joinpath(relocated, "code/replay.jl")
    text=read(`$(Base.julia_cmd()) --startup-file=no $("--project="*ROOT) $replay`, String)
    @test occursin("model=true", text)
    open(joinpath(relocated, "result.toml"), "a") do io
        write(io, "\n# deliberate tamper fixture\n")
    end
    @test_throws ErrorException read_r7_recovery(relocated)
    println("Energization hand evidence: ", relpath(folder, ROOT))
end

include("r7_flow_planning_fixtures.jl")
@testset "R9-RE1 R9-RE2 R9-RE3 R9-RE4 normal inheritance, planning and both R8 heat carriers" begin
    base, flow=joint_test_case(; limit = 0.8, battery_rule = "per_period_exclusive_v1")
    data=deepcopy(base.normal.data)
    data["electric"]["root_eligible"][2]=0
    normal=with_r7_electric_domain(
        with_r7_critical_load(
            R7NormalCase(data),
            [0.0 0 0 0; 0.2 0.3 0.5 0.4];
            provenance = "synthetic classified demand",
        ),
        "partial_energization_v1";
        provenance = "synthetic load node lacks grid-forming qualification",
    )
    c=R7PlanningCase(normal, base.specification)
    flow["case_sha256"]=c.sha256
    flow["normal_flow"]["case_sha256"]=normal.sha256
    @test PR.r7_partial_energization(PR.r7_event_template(c, 1).data)
    @test !haskey(base.normal.data["electric"], "recovery_domain")
    n=solve_r7_normal_flow(normal, flow["normal_flow"]; optimizer = OPT, budget_sec = 60)
    @test n["candidate_accepted"]
    ev=PR.r7_joint_event_values(c, n, 1)
    @test PR.r7_partial_energization(ev.case.data)
    folder=mktempdir(joinpath(ROOT, "tmp"); cleanup = false)
    for method in (:extensive, :finite_fault_ccg)
        r=solve_r7_planning(c; optimizer = OPT, method, budget_sec = 60)
        @test r["validation"]["robust_model_pass"]
        save_r7_planning(c, r, joinpath(folder, string(method)))
        @test read_r7_planning(joinpath(folder, string(method))).validation["robust_model_pass"]
    end
    r=solve_r7_flow_planning(c, flow; optimizer = OPT, budget_sec = 60)
    @test r["validation"]["robust_model_pass"]
    for mode in (:economic, :penalty, :threshold), carrier in (:detailed, :energy)
        if carrier==:detailed
            s=r8_spec(c, flow; mode, topology = :retain_surviving)
            rr=solve_r8_case(c, flow, s; optimizer = OPT, budget_sec = 60)
            @test rr["validation"]["primary_model_pass"]
            @test rr["validation"]["recovery_verified"]
            save_r8_run(c, flow, s, rr, joinpath(folder, string(mode)*"-detailed"))
            @test read_r8_run(joinpath(folder, string(mode)*"-detailed")).validation["recovery_verified"]
        else
            s=r8_energy_spec(
                c;
                pipe_capacity_MW = [2.0],
                mode,
                loss_rule = :lossless,
                topology = :retain_surviving,
            )
            rr=solve_r8_energy_case(c, s; optimizer = OPT, budget_sec = 60)
            @test rr["validation"]["primary_model_pass"]
            @test rr["validation"]["recovery_verified"]
            save_r8_energy_run(c, s, rr, joinpath(folder, string(mode)*"-energy"))
            @test read_r8_energy_run(joinpath(folder, string(mode)*"-energy")).validation["recovery_verified"]
        end
        for w in rr["evaluation"]["witnesses"]
            if w["fault"]==[1]
                @test vec(PR.r7_unpack(w["values"], "energized"))≈[1, 0] atol=1e-7
                @test vec(PR.r7_unpack(w["values"], "z"))==[0]
                @test PR.r7_unpack(w["values"], "P_shed_critical")[2, 1, 1]≈(
                    w["event"]==1 ? 0.3 : 0.5
                ) atol=1e-7
            end
        end
    end
    println("Energization planning evidence: ", relpath(folder, ROOT))
end
end
