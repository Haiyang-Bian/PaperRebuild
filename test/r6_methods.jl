module R6MethodTests
using Test, PaperRebuild, JuMP, HiGHS, TOML, SHA

function fixture()
    root=normpath(joinpath(@__DIR__, ".."))
    c=load_r6_physical_case(joinpath(root, "configs", "r6", "daily-small.toml"))
    d=TOML.parsefile(joinpath(root, "configs", "r6", "protocol.toml"))
    d["samples"]["train"]=12
    d["clustering"]["count"]=3
    p=R6Protocol(d)
    s=r6_generate_trajectories(p, "train")
    c, p, s, r6_fit_representatives(s, p)
end

@testset "R6-PHYSICAL common day and signed calls" begin
    c, p, s, reps=fixture()
    v=copy(s.values[:, :, 1])
    v[2, 1:3]=[1.0, -0.5, 0.0]
    day=r6_dispatch_day(c, v; id = "train_1")
    @test day.data["T"]*day.data["dt_h"]==24
    @test day.data["realtime"]["alpha_up"][1:3]==[1, 0, 0]
    @test day.data["realtime"]["alpha_down"][1:3]==[0, 0.5, 0]
    @test all(iszero, day.data["realtime"]["alpha_up"] .* day.data["realtime"]["alpha_down"])
    pv=only(a for a in day.data["devices"] if a["kind"]=="PV")
    @test pv["available_MW"]==pv["p_max_MW"] .* v[1, :]
    for k in ("electric", "heat", "buildings", "award", "ambient_K")
        @test day.data[k]==c.data["dispatch"][k]
    end
    @test c.data["dispatch"]["buildings"][1]["terminal_rule"]=="initial"
    @test c.data["dispatch"]["heat"]["terminal_rule"]=="free"
    @test_throws ErrorException r6_dispatch_day(c, ones(2, 4); id = "train_1")
    @test_throws ErrorException r6_dispatch_day(c, fill(2.0, 2, 24); id = "train_1")
    bad=deepcopy(c)
    bad.data["dispatch"]["ambient_K"][1]+=1
    @test_throws ErrorException r6_dispatch_day(bad, v; id = "train_1")
    bad=deepcopy(c.data)
    bad["dispatch"]["dt_h"]=0.25
    @test_throws ErrorException R6PhysicalCase(bad)
    bad=deepcopy(c.data)
    empty!(bad["dispatch"]["heat"]["pipes"][1]["history_S_K"])
    @test_throws ErrorException R6PhysicalCase(bad)
end

@testset "R6-METHOD six methods and held-out isolation" begin
    c, p, s, reps=fixture()
    cases=Dict{String,R5StrategicCase}()
    for method in PaperRebuild.R6_METHODS
        radius=method in ("DRO", "DRJCC") ? 0.01 : 0.0
        spec=R6MethodSpec(method; radius)
        x=r6_training_case(c, p, s, reps, spec)
        cases[method]=x
        @test x.data["market"]==c.data["market"]
        @test x.data["bid_bounds"]==c.data["bid_bounds"]
        @test x.data["risk"]["commitment"]["bounds"]==c.data["bounds"]
        @test x.data["provenance"]["r6"]["scope"]=="full_training_support"
        @test length(x.data["risk"]["commitment"]["scenarios"])==(method=="D" ? 1 : 3)
        b=build_r6_model(x)
        @test length(b.risk.base.first_stage["P_DA_MW"])==24
        @test all(
            q->q in (VariableRef, AffExpr, Vector{VariableRef}),
            first.(list_of_constraint_types(b.model)),
        )
        @test count(is_binary, all_variables(b.model))==(method in ("CCP", "DRJCC") ? 3 : 0)
        @test b.risk.pattern==(
            method in ("CCP", "DRJCC") ? nothing : zeros(Int, method=="D" ? 1 : 3)
        )
        @test x.data["risk"]["epsilon"]==(method in ("CCP", "DRJCC") ? 0.05 : 0.0)
    end
    nominal=only(cases["D"].data["risk"]["commitment"]["scenarios"])["case"]
    pv=only(a for a in nominal["devices"] if a["kind"]=="PV")
    @test pv["available_MW"]≈pv["p_max_MW"]*vec(sum(s.values[1, :, :]; dims = 2))/12
    @test all(iszero, vcat(nominal["realtime"]["alpha_up"], nominal["realtime"]["alpha_down"]))
    @test cases["RO"].data["risk"]["ambiguity"]["radius"]==maximum(r6_support_distance(s, reps))
    dev=r6_training_case(c, p, s, reps, R6MethodSpec("SP"); development_count = 2)
    @test dev.data["provenance"]["r6"]["scope"]=="development_subset"
    @test sum(x["probability"] for x in dev.data["risk"]["commitment"]["scenarios"])≈1
    @test dev.data["provenance"]["r6"]["selected_training_ids"]==reps["representative_ids"][1:2]
    @test_throws ErrorException r6_training_case(
        c,
        p,
        s,
        reps,
        R6MethodSpec("SP");
        development_count = 0,
    )
    for split in ("validation", "test")
        other=r6_generate_trajectories(p, split)
        @test_throws ErrorException r6_training_case(c, p, other, reps, R6MethodSpec("SP"))
    end
    bad=deepcopy(reps)
    bad["probabilities"][1]+=0.01
    @test_throws ErrorException r6_training_case(c, p, s, bad, R6MethodSpec("SP"))
    @test_throws ErrorException r6_training_case(c, p, s, reps, R6MethodSpec("CCP"; epsilon = 0.1))
    @test_throws ErrorException R6MethodSpec("other")
    @test_throws ErrorException R6MethodSpec("SP"; radius = 0.01)
    @test_throws ErrorException R6MethodSpec("DRO"; radius = NaN)
    bad=deepcopy(cases["SP"].data)
    bad["risk"]["epsilon"]=0.5
    @test_throws ErrorException build_r6_model(R5StrategicCase(bad))
    bad=deepcopy(cases["D"].data)
    bad["risk"]["commitment"]["scenarios"][1]["case"]["realtime"]["alpha_up"][1]=0.1
    @test_throws ErrorException build_r6_model(R5StrategicCase(bad))
    unsupported=solve_r6_training(
        cases["SP"];
        optimizer = HiGHS.Optimizer,
        oracle_optimizer = HiGHS.Optimizer,
        budget_sec = 60.0,
    )
    @test unsupported["status"]=="unsupported_solver"
    @test !unsupported["validation"]["model_pass"]
    @test !unsupported["cost_optimization_complete"]
end

@testset "R6-ROBUST expectation, finite-support maximum and separate risk" begin
    opt=optimizer_with_attributes(
        HiGHS.Optimizer,
        "primal_feasibility_tolerance"=>1e-9,
        "dual_feasibility_tolerance"=>1e-9,
    )
    weights=[0.25, 0.75]
    D=[0.0 0.4; 0.4 0.0]
    # 解析：可移质量rho/0.4，费用增加8乘该质量，最大只需移走0.25。
    for (rho, expected) in ((0.0, 4.0), (0.02, 4.4), (maximum(D), 6.0))
        r=r5_worst_distribution(weights, D, [-2.0, 6.0], rho; optimizer = opt)
        @test r["validation"]["pass"]
        @test r["validation"]["primal_value"]≈expected atol=1e-8
    end
    r=r5_worst_distribution(weights, D, [1.0, 0.0], 0.02; optimizer = opt, quantity = :probability)
    @test r["validation"]["pass"]
    @test r["validation"]["primal_value"]≈0.3 atol=1e-8
end
end
