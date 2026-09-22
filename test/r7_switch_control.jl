using PaperRebuild, JuMP, HiGHS, Test, TOML

let
    pr=PaperRebuild
    root=dirname(@__DIR__)
    opt=optimizer_with_attributes(
        HiGHS.Optimizer,
        "threads"=>1,
        "primal_feasibility_tolerance"=>1e-9,
        "dual_feasibility_tolerance"=>1e-9,
    )
    @testset "R9-RW1 declared switches, forced faults and actual LP rows" begin
        d=TOML.parsefile(joinpath(root, "configs/r7/inner-tie-two-hour.toml"))
        d["devices"]=[
            Dict("id"=>"GT1", "kind"=>"GT", "electric_node"=>1, "P_max_MW"=>0.8, "Q_max_Mvar"=>0.5),
        ]
        d["electric"]["root_eligible"]=[1, 0, 0]
        for k in ("source_flow_max", "load_flow_max")
            d["heat"][k]=zeros(2)
        end
        d["heat"]["load_MW"]=[zeros(2), zeros(2)]
        old=with_r7_electric_domain(
            R7RecoveryCase(d),
            "partial_energization_v1";
            provenance = "synthetic GT island with zero heat demand",
        )
        all=with_r7_switch_control(
            old,
            [[1, 2], [2, 3], [1, 3]];
            provenance = "explicit legacy-equivalent set",
        )
        tie=with_r7_switch_control(
            old,
            [[3, 1]];
            provenance = "only normally open tie has actuator",
        )
        none=with_r7_switch_control(old, Vector{Int}[]; provenance = "no active switching")
        @test !haskey(old.data["electric"], "switch_control")
        @test pr.r7_switch_control_mask(tie.data)==[false, false, true]
        @test pr.r7_switch_admissible(tie, [1, 0, 0], [0, 1, 1])
        @test !pr.r7_switch_admissible(tie, [0, 0, 0], [0, 1, 0])
        @test !pr.r7_switch_admissible(none, [1, 0, 0], [0, 1, 1])
        results=Dict()
        for (id, c, fault) in (
            ("legacy", old, [1, 0, 0]),
            ("all", all, [1, 0, 0]),
            ("tie", tie, [1, 0, 0]),
            ("none", none, [1, 0, 0]),
            ("healthy", none, [0, 0, 0]),
        )
            r=solve_r7_recovery(c, fault; optimizer = opt, budget_sec = 60)
            @test r["candidate_accepted"]
            @test r["solver_objective_MWh"]≈(id=="none" ? 1.2 : 0.0) atol=1e-7
            results[id]=r
        end
        @test sum(pr.r7_unpack(results["tie"]["values"], "a_on"))≈1 atol=1e-8
        @test sum(pr.r7_unpack(results["tie"]["values"], "a_off"))≈0 atol=1e-8
        @test sum(pr.r7_unpack(results["none"]["values"], "a_off"))≈0 atol=1e-8
        @test_throws ErrorException build_r7_recovery(
            none,
            [1, 0, 0];
            fixed_z = [0, 1, 1],
            fixed_energized = [1, 1, 1],
        )
        for edges in ([[1, 3], [3, 1]], [[2, 2]], [[1, 4]], [[1.0, 3.0]], [Any[true, 3]])
            @test_throws ErrorException with_r7_switch_control(old, edges; provenance = "bad")
        end
        @test_throws ErrorException with_r7_switch_control(old, []; provenance = "")
        bad=deepcopy(results["tie"])
        bad["case_sha256"]=none.sha256
        checked=validate_r7_recovery(none, bad)
        @test !checked["model_pass"]
        @test any(startswith(x["id"], "R9-RW1") && !x["pass"] for x in checked["rows"])

        # 同一个固定开关/带电模式只在相应故障下可用；抽取时不能用无故障排除它。
        mode=Dict("switch"=>[0, 1, 1], "energized"=>[1, 1, 1])
        lp=r7_recovery_lp(tie, mode)
        for fault in ([1, 0, 0], [0, 0, 0])
            dual=build_r7_recourse_dual(lp, fault; optimizer = opt)
            set_silent(dual.model)
            optimize!(dual.model)
            if fault[1]==1
                @test termination_status(dual.model)==MOI.OPTIMAL
                check=validate_r7_dual(lp, fault, value.(dual.lambda))
                @test check["dual_feasible"]
                @test check["dual_objective_MWh"]≈0 atol=1e-7
            else
                @test termination_status(dual.model) in
                      (MOI.DUAL_INFEASIBLE, MOI.INFEASIBLE_OR_UNBOUNDED)
            end
        end
        # 全节点域使用同一开关限制，不仅在partial域中生效。
        full=with_r7_electric_domain(
            tie,
            "all_nodes_energized_v1";
            provenance = "domain comparison",
        )
        @test pr.r7_topology_roots(full, [0, 0, 0], [0, 1, 0])===nothing
        @test pr.r7_topology_roots(full, [1, 0, 0], [0, 1, 1])!==nothing
        enumeration=enumerate_r7_recovery(none, [1, 0, 0]; optimizer = opt, budget_sec = 60)
        @test enumeration["gap_certified"]
        @test enumeration["upper_bound_MWh"]≈1.2 atol=1e-7
        dest=mktempdir(joinpath(root, "tmp"); cleanup = false)
        save_r7_recovery(tie, results["tie"], joinpath(dest, "tie"))
        @test read_r7_recovery(joinpath(dest, "tie")).validation["model_pass"]
        replay=joinpath(dest, "tie", "code", "replay.jl")
        @test occursin(
            "model=true",
            read(`$(Base.julia_cmd()) --startup-file=no $("--project="*root) $replay`, String),
        )
        open(joinpath(dest, "tie", "case.toml"), "a") do io
            write(io, "\n# deliberate integrity test\n")
        end
        @test_throws ErrorException read_r7_recovery(joinpath(dest, "tie"))
        println("Switch domain development evidence: ", relpath(dest, root))
    end
    @testset "R9-RW1 normal and event input inheritance" begin
        old=load_r7_normal_case(joinpath(root, "configs/r7/normal-hand.toml"))
        c=with_r7_switch_control(old, []; provenance = "synthetic no active switches")
        @test !haskey(old.data["electric"], "switch_control")
        n=solve_r7_normal(c; optimizer = opt, budget_sec = 60)
        @test n["candidate_accepted"]
        ev=r7_normal_event(
            c,
            n;
            event_start = 2,
            periods = 1,
            renewable_factor = 0.4,
            loss_limit_MWh = 1.0,
        )
        @test ev.case.data["electric"]["switch_control"]==c.data["electric"]["switch_control"]
        planning=R7PlanningCase(c, TOML.parsefile(joinpath(root, "configs/r7/planning-hand.toml")))
        @test pr.r7_event_template(planning, 1).data["electric"]["switch_control"]==c.data["electric"]["switch_control"]
    end
end
