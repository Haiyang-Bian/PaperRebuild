using Test, JuMP, Clarabel, TOML

@testset "R4 discrete audit" begin
    c=load_r4_case(joinpath(@__DIR__, "..", "configs", "r4", "baseline", "open_flexible.toml"))
    patterns=r4_battery_patterns(c)
    @test length(patterns)==16
    @test length(unique(patterns))==16
    @test patterns[6]==[1, 0, 1, 0]
    @test patterns[11]==[0, 1, 0, 1]
    # 一时段仍有两个模式，但初末能量相等使其均为空闲：解析验证重复可行域保留。
    d=deepcopy(c.data)
    d["T"]=1
    d["grid_price"]=d["grid_price"][1:1]
    for a in d["actors"], key in ("P_load", "H_load", "PV_profile", "P_preferred", "H_preferred")
        a[key]=a[key][1:1]
    end
    tiny=R4Case(d)
    opt=optimizer_with_attributes(
        Clarabel.Optimizer,
        "tol_feas"=>1e-9,
        "tol_gap_abs"=>1e-9,
        "tol_gap_rel"=>1e-9,
    )
    central=solve_r4_discrete(tiny; optimizer = opt, method = :central_enumeration, budget_sec = 60)
    v=central["validation"]
    @test v["all_modes_attempted"]
    @test v["accepted_model_count"]==2
    @test v["cost_optimization_complete"]
    @test v["relative_gap"]<=1e-4
    costs=[x["operating_cost"] for x in v["mode_checks"]]
    @test maximum(costs)-minimum(costs)<1e-5
    for row in central["records"]
        s=row["reconstruction"]["candidate"]["values"]
        @test maximum(abs, s["P_ch"][2])<1e-7
        @test maximum(abs, s["P_dis"][2])<1e-7
    end
    raw=deepcopy(central["records"][1]["raw"])
    raw["values"]["w_P"][2][1]+=1
    raw["solver_objective"]+=1
    saved=deepcopy(raw)
    fixed=reconstruct_r4_cost(tiny, raw)
    @test isequal(raw, saved)
    @test fixed["candidate"]["validation"]["model_pass"]
    @test !fixed["new_solver_certificate"]
    @test !fixed["candidate"]["cost_optimization_complete"]
    @test fixed["actual_cost_unchanged"]
    @test fixed["candidate"]["values"]["P_D"]==raw["values"]["P_D"]
    @test fixed["candidate"]["solver_objective"]<raw["solver_objective"]
    dist=solve_r4_discrete(tiny; optimizer = opt, budget_sec = 60)
    @test dist["validation"]["all_modes_attempted"]
    @test dist["validation"]["accepted_model_count"]==2
    @test !dist["validation"]["cost_optimization_complete"]
    @test isnan(dist["validation"]["objective_bound"])
    @test abs(dist["validation"]["best_model_cost"]-v["best_model_cost"])/max(
        1,
        v["best_model_cost"],
    )<=1e-3
    for mutate in (
        x->(x["records"][1]["modes"][1]=1),
        x->(x["records"][1]["reconstruction"]["control_sha256"]="changed"),
        x->pop!(x["records"]),
        x->(x["records"][1]["reconstruction"]["candidate"]["values"]["P_D"][2][1]+=0.01),
    )
        bad=deepcopy(central)
        mutate(bad)
        @test_throws ErrorException validate_r4_discrete(tiny, bad)
    end
    timed=solve_r4_discrete(tiny; optimizer = opt, budget_sec = 1e-12)
    @test timed["status"]=="enumeration_budget_exhausted"
    @test timed["validation"]["best_model_index"]==0
    @test timed["validation"]["attempted_modes"]==0
    failed=solve_r4_discrete(
        tiny;
        optimizer = ()->error("license missing fixture"),
        budget_sec = 60,
    )
    @test all(x["status"]=="license_missing" for x in failed["records"])
    @test failed["validation"]["best_model_index"]==0
    @test_throws ErrorException solve_r4_discrete(tiny; optimizer = opt, method = :unknown)
    @test_throws ErrorException solve_r4_discrete(tiny; optimizer = opt, budget_sec = 0)
    mktempdir() do dir
        path=save_r4_discrete_run(tiny, central; directory = dir, run_id = "audit")
        @test isequal(read_r4_discrete_run(path).validation, v)
        @test_throws ErrorException save_r4_discrete_run(
            tiny,
            central;
            directory = dir,
            run_id = "audit",
        )
        open(joinpath(path, "result.toml"), "a") do io
            write(io, "\n# tamper\n")
        end
        @test_throws ErrorException read_r4_discrete_run(path)
    end
end
