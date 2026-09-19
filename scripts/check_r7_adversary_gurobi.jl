push!(LOAD_PATH, normpath(joinpath(@__DIR__, "..")))
using PaperRebuild, JuMP, Gurobi, Test, TOML

function main(args)
    length(args)==1 || error("usage: check_r7_adversary_gurobi.jl NEW_DIRECTORY")
    ispath(args[1]) && error("不覆盖已有运行")
    env=Gurobi.Env(Dict{String,Any}("OutputFlag"=>0))
    opt=optimizer_with_attributes(
        ()->Gurobi.Optimizer(env),
        "Threads"=>1,
        "Seed"=>0,
        "FeasibilityTol"=>1e-9,
        "OptimalityTol"=>1e-9,
        "IntFeasTol"=>1e-9,
        "MIPGap"=>1e-9,
        "DualReductions"=>0,
    )
    c=load_r7_recovery_case(joinpath(@__DIR__, "..", "configs/r7/recovery-hand.toml"))
    r=solve_r7_adversary(c; optimizer = opt)
    save_r7_adversary(c, r, joinpath(args[1], "hand"))
    @testset "R7-native-indicator-oracle" begin
        @test r["validation"]["gap_certified"]
        @test r["validation"]["lower_bound_MWh"]≈17/30 atol=1e-7
        @test r["validation"]["upper_bound_MWh"]≈17/30 atol=1e-7
        @test r["validation"]["threshold_status"]=="violation_certified"
        d=deepcopy(c.data)
        d["devices"][1]["P_min_MW"]=0.2
        bad=R7RecoveryCase(d)
        rr=solve_r7_adversary(bad; optimizer = opt)
        save_r7_adversary(bad, rr, joinpath(args[1], "infeasible"))
        @test rr["validation"]["infeasible_recovery_certified"]
        @test rr["validation"]["lower_bound_MWh"]==Inf
        @test rr["validation"]["upper_bound_MWh"]==Inf
        @test rr["validation"]["threshold_status"]=="violation_certified"
    end
    @testset "R7-I6-nested-plan-and-original-evidence" begin
        root=normpath(joinpath(@__DIR__, ".."))
        for (label, normal, spec, expected) in (
            ("reserve", "normal-reserve-hand.toml", "planning-reserve-hand.toml", 193.275),
            ("legacy", "normal-hand.toml", "planning-hand.toml", Inf),
        )
            pc=load_r7_planning_case(
                joinpath(root, "configs/r7", normal),
                joinpath(root, "configs/r7", spec),
            )
            pr=solve_r7_planning(
                pc;
                optimizer = opt,
                method = :nested_indicator_ccg,
                budget_sec = 600,
            )
            save_r7_planning(pc, pr, joinpath(args[1], label*"_nested"))
            if isfinite(expected)
                @test pr["candidate_accepted"]
                @test pr["conditional_cost_complete"]
                @test pr["validation"]["cost_USD"]≈expected atol=1e-6
                @test all(
                    a["oracle"]["schema"]=="r7-adversary-result-v1" for it in pr["iterations"] for
                    a in it["audits"]
                )
            else
                @test pr["status"]=="infeasible_certified"
                @test !pr["candidate_accepted"]
            end
        end
        changed=deepcopy(r)
        changed["iterations"][end]["master"]["values"]["blocks"][1]["lambda"][1]=1.0
        @test_throws Exception validate_r7_adversary(c, changed)
        changed=deepcopy(r)
        changed["preplan_id"]="different_plan"
        @test_throws Exception validate_r7_adversary(c, changed)
        changed=deepcopy(r)
        changed["iterations"][end]["master"]["solver_upper_bound_MWh"]=-1.0
        @test_throws Exception validate_r7_adversary(c, changed)
        mktempdir() do dir
            cp(joinpath(args[1], "hand"), joinpath(dir, "tampered"))
            open(joinpath(dir, "tampered/result.toml"), "a") do io
                write(io, "\n# altered\n")
            end
            @test_throws Exception read_r7_adversary(joinpath(dir, "tampered"))
        end
    end
end
main(ARGS)
