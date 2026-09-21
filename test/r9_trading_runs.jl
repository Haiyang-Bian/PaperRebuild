using JuMP, Clarabel, TOML, SHA
isdefined(@__MODULE__, :r9_trading_fixture) || include("fixtures/r9_trading.jl")

function r9_run_modes(c; charge = 0)
    G, T=length(c.data["devices"]), c.data["T"]
    z=zeros(Int, G, T)
    for (i, g) in enumerate(c.data["devices"])
        g["kind"] in ("BS", "HS") && (z[i, :].=charge)
    end
    Dict("z_storage"=>z, "heat_direction"=>ones(Int, length(c.data["heat"]["pipes"]), T))
end

# 只在测试副本上更新载体哈希，以检验独立回代而非仅检验文件哈希。
function r9_test_rehash(path, relative)
    file=joinpath(path, "hashes.toml")
    meta=TOML.parsefile(file)
    meta["files"][relative]=bytes2hex(sha256(read(joinpath(path, relative))))
    write(file, PaperRebuild.r4_text(meta))
end

@testset "R9 trading shared budget and raw stage states" begin
    c=r9_trading_fixture()
    modes=r9_run_modes(c)
    calls=Ref(0)
    never=()->(calls[]+=1; error("optimizer must not start"))
    for operation in (:central, :independent)
        r=solve_r9_trading_case(c; optimizer = never, operation, budget_sec = 0.0, modes)
        @test calls[]==0 && !r["validation"]["model_pass"]
        @test length(r["stages"])==1 && !haskey(first(r["stages"]), "values")
        @test first(r["stages"])["status"]=="time_limit_no_solution"
        @test validate_r9_trading_run(c, r)==r["validation"]
    end
    r=solve_r9_trading_case(
        c;
        optimizer = never,
        budget_sec = 60.0,
        deadline = PaperRebuild.r3_clock()-1.0,
        modes,
    )
    @test calls[]==0 && r["deadline_expired_at_start"] && !r["wall_budget_pass"]
    @test r["available_budget_sec"]==0.0
    @test_throws ErrorException solve_r9_trading_case(c; optimizer = never, budget_sec = 601)
    @test_throws ErrorException solve_r9_trading_case(c; optimizer = never, deadline = Inf)
    for (factory, state) in (
        (() -> error("license unavailable in test"), "license_missing"),
        (() -> error("numerical test failure"), "numerical_failure"),
    )
        r=solve_r9_trading_case(c; optimizer = factory, budget_sec = 60.0, modes)
        @test r["status"]==state && !r["validation"]["model_pass"]
        @test !haskey(first(r["stages"]), "values")
        @test validate_r9_trading_run(c, r)==r["validation"]
    end
    r=solve_r9_trading_case(c; optimizer = Clarabel.Optimizer, budget_sec = 60.0)
    @test r["status"]=="unsupported_solver"
    @test !r["validation"]["model_pass"] && r["mode_rule"]=="free_integer"
end

@testset "R9 trading independent plans and network feasibility are separate" begin
    c=r9_trading_fixture()
    modes=r9_run_modes(c)
    central=solve_r9_trading_case(c; optimizer = Clarabel.Optimizer, modes, budget_sec = 60.0)
    @test central["validation"]["model_pass"] && central["validation"]["ledger_pass"]
    @test central["system_cost_CNY"]≈100.0 atol=1e-4
    @test !central["validation"]["full_thermal_physics_certified"]
    @test validate_r9_trading_run(c, central)==central["validation"]
    ag0=solve_r9_trading_case(
        c;
        optimizer = Clarabel.Optimizer,
        operation = :independent,
        modes,
        budget_sec = 60.0,
    )
    @test length(ag0["stages"])==3 && ag0["primary_stage_index"]==3
    @test ag0["validation"]["model_pass"] && ag0["validation"]["local_plans_pass"]
    @test ag0["system_cost_CNY"]≈100.0 atol=1e-4
    @test all(p["kind"]!="p2p" && p["kind"]!="service" for p in ag0["ledger"]["payments"])
    @test ag0["stages"][3]["frozen_plans"][1]["values"]==ag0["stages"][1]["values"]
    @test ag0["stages"][3]["allocated_budget_sec"]<=ag0["available_budget_sec"]
    bad=deepcopy(ag0)
    bad["stages"][3]["frozen_plans"][1]["values"]["P_D"][2][1]+=0.1
    @test_throws ErrorException validate_r9_trading_run(c, bad)
    for edit in (
        r->(r["stages"][1]["objective_kind"]="diagnostic"),
        r->(r["stages"][1]["fixed_modes"]["heat_direction"]=[[1]]),
        r->(r["stages"][1]["fixed_modes"]["heat_direction"][1][1]=2),
        r->(r["stages"][1]["allocated_budget_sec"]=600.0),
        r->(r["full_thermal_physics_certified"]=true),
        r->(r["cost_optimization_complete"]=!r["cost_optimization_complete"]),
    )
        bad=deepcopy(ag0)
        edit(bad)
        @test_throws ErrorException validate_r9_trading_run(c, bad)
    end
    d=deepcopy(c.data)
    d["devices"][2]["power_max_MW"]=0.5
    d["devices"][2]["availability_MW"]=[0.5]
    impossible=R9TradingCase(d)
    failed=solve_r9_trading_case(
        impossible;
        optimizer = Clarabel.Optimizer,
        operation = :independent,
        modes,
        budget_sec = 60.0,
    )
    @test failed["validation"]["local_plans_pass"]
    @test failed["status"]=="network_infeasible_certified"
    @test !failed["validation"]["model_pass"] && !haskey(failed, "system_cost_CNY")
    @test length(failed["stages"])==3 && !haskey(last(failed["stages"]), "values")

    # 人工构造停止状态fixture：同一已保存候选不能因限时被删除，亦不能冒称最优。
    for has_candidate in (true, false)
        stage=deepcopy(first(central["stages"]))
        !has_candidate && foreach(
            k->pop!(stage, k, nothing),
            ("values", "solver_objective", "objective_bound", "relative_gap", "bound_upper_excess"),
        )
        stage["termination"]="TIME_LIMIT"
        stage["primal"]=has_candidate ? "FEASIBLE_POINT" : "NO_SOLUTION"
        stage["status"]=has_candidate ? "time_limit_with_incumbent" : "time_limit_no_solution"
        stage["cost_optimization_complete"]=false
        v=PaperRebuild.r9_trading_checked_stage(c, stage)
        @test !PaperRebuild.r9_trading_stage_certificate(stage, v)
        @test v["model_pass"]==has_candidate
    end
end

@testset "R9 trading immutable frozen replay and declared comparison domain" begin
    mktempdir() do directory
        c=r9_trading_fixture(; store = true)
        modes=r9_run_modes(c)
        r=solve_r9_trading_case(c; optimizer = Clarabel.Optimizer, modes, budget_sec = 60.0)
        @test r["validation"]["model_pass"]
        p=save_r9_trading_run(c, r; directory, run_id = "central")
        loaded=read_r9_trading_run(p)
        @test loaded.validation_source=="frozen_source"
        @test loaded.case.sha256==c.sha256 && loaded.validation==r["validation"]
        @test loaded.result["stages"][1]["values"]==r["stages"][1]["values"]
        @test_throws ErrorException save_r9_trading_run(c, r; directory, run_id = "central")
        @test_throws ErrorException PaperRebuild.r9_trading_path(p, "../outside")
        @test_throws ErrorException PaperRebuild.r9_trading_path(p, "C:/outside")
        @test_throws ErrorException PaperRebuild.r9_trading_path(p, "snapshot//src/a.jl")
        changed=deepcopy(r)
        changed["source_unchanged"]=false
        @test_throws ErrorException save_r9_trading_run(
            c,
            changed;
            directory,
            run_id = "wrong-source",
        )
        @test !ispath(joinpath(directory, "wrong-source"))
        ag0=solve_r9_trading_case(
            c;
            optimizer = Clarabel.Optimizer,
            operation = :independent,
            modes,
            budget_sec = 60.0,
        )
        p0=save_r9_trading_run(c, ag0; directory, run_id = "independent")
        compared=compare_r9_trading_runs([p, p0])
        @test length(compared["rows"])==2 && length(compared["differences"])==1
        pair=only(compared["differences"])
        @test pair["comparable_feasible_candidates"] == (
            loaded.validation["adopted_physical_pass"] &&
            ag0["validation"]["adopted_physical_pass"]
        )
        @test pair["comparable_feasible_candidates"] ||
              !haskey(pair, "resource_cost_difference_percent")
        other=solve_r9_trading_case(
            c;
            optimizer = Clarabel.Optimizer,
            modes = r9_run_modes(c; charge = 1),
            budget_sec = 60.0,
        )
        p1=save_r9_trading_run(c, other; directory, run_id = "other-choices")
        @test_throws ErrorException compare_r9_trading_runs([p, p1])

        # 当前源码只用于以下测试副本的语义篡改；正式重验默认使用冻结源码。
        for (name, rel, edit) in (
            ("input", "input.toml", x->replace(x, "synthetic"=>"forged")),
            (
                "values",
                "result.toml",
                x->replace(x, "system_cost_CNY = "=>"system_cost_CNY = 10 # "),
            ),
            ("residual", "residuals/stage-01.csv", x->replace(x, ",MW,"=>",MWh,")),
        )
            copy_path=joinpath(directory, name)
            cp(p, copy_path)
            file=joinpath(copy_path, rel)
            write(file, edit(read(file, String)))
            @test_throws Exception read_r9_trading_run(copy_path)
            r9_test_rehash(copy_path, rel)
            @test_throws Exception read_r9_trading_run(copy_path; frozen = false)
        end
        zero=solve_r9_trading_case(
            c;
            optimizer = ()->error("must not start"),
            modes,
            budget_sec = 0.0,
        )
        pzero=save_r9_trading_run(c, zero; directory, run_id = "no-budget")
        empty=read_r9_trading_run(pzero; frozen = false)
        @test !empty.validation["model_pass"] && !haskey(empty.result, "ledger")
        @test isempty(
            PaperRebuild.r9_trading_checked_stage(c, first(empty.result["stages"]))["rows"],
        )
    end
end
