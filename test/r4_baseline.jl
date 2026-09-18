using Test, JuMP, Clarabel, TOML

@testset "R4 fixed preference and implementable baseline" begin
    root=normpath(joinpath(@__DIR__, ".."))
    legacy=load_r4_case(joinpath(root, "configs", "r4", "base.toml"))
    c=load_r4_case(joinpath(root, "configs", "r4", "baseline", "import_flexible.toml"))
    fixed=load_r4_case(joinpath(root, "configs", "r4", "baseline", "import_fixed.toml"))
    open_case=load_r4_case(joinpath(root, "configs", "r4", "baseline", "open_flexible.toml"))
    for i in 1:3, carrier in ("P", "H")
        @test c.data["actors"][i][carrier*"_preferred"] ==
              fixed.data["actors"][i][carrier*"_preferred"]
        @test all(
            r4_preferred_demand(c.data["actors"][i], carrier, t) ==
            r4_preferred_demand(legacy.data["actors"][i], carrier, t) for t in 1:4
        )
    end
    @test_throws ErrorException r4_preferred_demand(c.data["actors"][2], "Q", 1)
    for bad in (fill(NaN, 4), [-1.0, 0, 0, 0], [0.2], fill(Inf, 4))
        d=deepcopy(c.data)
        d["actors"][2]["P_preferred"]=bad
        @test_throws ErrorException R4Case(d)
    end
    for key in ("preference_model", "admission_policy")
        d=deepcopy(c.data)
        d[key]="silent_fallback"
        @test_throws ErrorException R4Case(d)
    end
    d=deepcopy(c.data)
    delete!(d["actors"][2], "H_preferred")
    @test_throws ErrorException R4Case(d)
    d=deepcopy(c.data)
    delete!(d, "preference_model")
    @test_throws ErrorException R4Case(d)

    opt=optimizer_with_attributes(
        Clarabel.Optimizer,
        "tol_feas"=>1e-9,
        "tol_gap_abs"=>1e-9,
        "tol_gap_rel"=>1e-9,
    )
    # 共用既有枚举：不引入整数松弛，求解与独立验收使用相同输入。
    central=solve_r4_case(c; optimizer = opt, enumerate_battery = true, budget_sec = 60)
    independent=solve_r4_case(
        c;
        optimizer = opt,
        spec = R4Spec(operation = :independent),
        enumerate_battery = true,
        budget_sec = 60,
    )
    fixed_run=solve_r4_case(fixed; optimizer = opt, enumerate_battery = true, budget_sec = 60)
    for r in (central, independent, fixed_run)
        @test r["validation"]["model_pass"]
        @test r["validation"]["electric_original_pass"]
        @test r["validation"]["ledger_pass"]
        @test get(r, "relative_gap", Inf)<=1e-4
        @test r["spec"]["version"]=="r4_baseline_checked_v1"
    end
    @test length(independent["local_stages"])==2
    @test all(l["validation"]["model_pass"] for l in independent["local_stages"])
    @test central["operating_cost"]<=fixed_run["operating_cost"]+1e-4
    @test central["operating_cost"]<=independent["operating_cost"]+1e-4
    @test all(x["net_MW"]<=3e-6 for x in independent["ledger"]["contracts"])
    gain=r4_coordination_surplus(c, independent, central)
    @test gain["eligible"]
    @test gain["accounting_identity_pass"]
    @test gain["bargaining"]=="not_performed"
    @test sum(x["utility_gain"] for x in gain["actors"])≈gain["resource_saving"] atol=1e-6
    @test_throws ErrorException r4_coordination_surplus(fixed, independent, central)
    @test_throws ErrorException r4_coordination_surplus(c, central, independent)
    missing=deepcopy(independent)
    delete!(missing, "values")
    denied=r4_coordination_surplus(c, missing, central)
    @test !denied["eligible"]
    @test !haskey(denied, "saving_fraction")
    changed=deepcopy(independent)
    changed["values"]["P_PV"][2][1]+=1.0
    check=validate_r4_solution(c, changed)
    @test !check["model_pass"]
    @test any(x["equation"]=="R4-B2-P" && !x["pass"] for x in check["rows"])

    # 仅购能不保证供给足够，不能跳过网络/设备约束。
    d=deepcopy(c.data)
    d["actors"][3]["H_load"]=fill(10.0, 4)
    capacity=R4Case(d)
    failed=solve_r4_case(capacity; optimizer = opt, enumerate_battery = true, budget_sec = 60)
    @test failed["status"]=="infeasible_certified"
    @test !failed["validation"]["model_pass"]

    # 旧数值的偏好和残差仍完全相同；如原档案本地存在，则逐条重读验证。
    oldpath=joinpath(root, "results", "runs", "r4", "r4-central-20260918")
    if isdir(oldpath)
        entries=TOML.parsefile(joinpath(oldpath, "study.toml"))["runs"]
        @test length(entries)==19
        for entry in entries
            rr=read_r4_run(joinpath(oldpath, entry["directory"]))
            @test rr.result["spec"]["version"]=="r4_central_checked_v1"
        end
    end
    mktempdir() do dir
        path=save_r4_run(c, independent; directory = dir, run_id = "baseline")
        @test read_r4_run(path).validation==independent["validation"]
    end
    # 开放新配置仅显式写出原锚点，并没有改变原科学模型。
    for stage in (:central, :local)
        b=build_r4_model(open_case; stage, actor = stage==:local ? 2 : 0, modes = zeros(Int, 4))
        old=build_r4_model(legacy; stage, actor = stage==:local ? 2 : 0, modes = zeros(Int, 4))
        @test b.model_types==old.model_types
        @test num_variables(b.model)==num_variables(old.model)
        @test num_constraints(b.model; count_variable_in_set_constraints = true) ==
              num_constraints(old.model; count_variable_in_set_constraints = true)
    end
end
