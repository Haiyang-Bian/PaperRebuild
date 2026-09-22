using Test, JuMP, Clarabel, TOML
const R4ROOT=normpath(joinpath(@__DIR__, ".."))
const R4OPT=optimizer_with_attributes(
    Clarabel.Optimizer,
    "tol_feas"=>1e-9,
    "tol_gap_abs"=>1e-9,
    "tol_gap_rel"=>1e-9,
)

@testset "R4 model and ledger" begin
    c=load_r4_case(joinpath(R4ROOT, "configs", "r4", "base.toml"))
    @test PaperRebuild.r4_loss(c.data["heat"]["pipes"][1])≈0.0018
    @test_throws ErrorException R4Spec(operation = :AG0)
    @test_throws ErrorException R4Spec(electric = :silent_fallback)
    for bad in ("sat_P", "sat_H", "BS_cost", "CHP_max", "retail_limit")
        d=deepcopy(c.data)
        d["actors"][2][bad]=-1.0
        @test_throws ErrorException R4Case(d)
    end
    for bad in ("CHP_max", "COP_HP", "retail_limit", "port_flow_max")
        d=deepcopy(c.data)
        d["actors"][2][bad]=Inf
        @test_throws ErrorException R4Case(d)
    end
    d=deepcopy(c.data)
    d["units"]["power"]="kW"
    @test_throws ErrorException R4Case(d)
    d=deepcopy(c.data)
    d["actors"][2]["P_load"]=[0.1]
    @test_throws ErrorException R4Case(d)
    d=deepcopy(c.data)
    d["actors"][2]["retail_limit"]=0.01
    @test_throws ErrorException R4Case(d)
    @test_throws ErrorException build_r4_model(c; stage = :network)
    @test_throws ErrorException build_r4_model(c; modes = [0, 0])
    @test_throws ErrorException solve_r4_case(c; optimizer = R4OPT, budget_sec = 0)
    b=build_r4_model(c; modes = [0, 1, 0, 1])
    @test termination_status(b.model)==MOI.OPTIMIZE_NOT_CALLED
    @test b.model_class=="SOCP"
    @test all(!occursin("ScalarNonlinear", s) for s in b.model_types)
    @test build_r4_model(c).model_class=="MISOCP"
    @test build_r4_model(c; spec = R4Spec(electric = :exact)).model_class=="nonconvex_quadratic"

    # 16个连续凸子问题；A2同模型界与A1独立回代。
    r=solve_r4_case(c; optimizer = R4OPT, enumerate_battery = true, budget_sec = 60)
    @test r["status"]=="solver_optimal"
    @test r["enumeration_expected"]==16
    @test r["validation"]["model_pass"]
    @test r["validation"]["electric_original_pass"]
    @test r["validation"]["heat_pass"]
    @test r["validation"]["ledger_pass"]
    @test get(r, "relative_gap", Inf)<=1e-4
    @test r["cost_optimization_complete"]
    s=r["values"]
    l=r["ledger"]
    @test abs(l["cash_balance"])<1e-8
    @test abs(l["utility_identity"])<1e-8
    @test all(abs(s["E"][i][end]-s["E"][i][1])<1e-6 for i in 1:3)
    @test all(min(s["P_ch"][2][t], s["P_dis"][2][t])<1e-6 for t in 1:4)
    fees=sum(x["amount"] for x in l["payments"] if x["kind"]=="service")
    peerenergy=sum(x["quantity_MWh"] for x in l["payments"] if x["kind"]=="p2p")
    @test fees≈5peerenergy atol=1e-10
    alternative=deepcopy(c.data["settlement"])
    alternative["P_peer"]=150.0
    alternative["H_peer"]=110.0
    alt=r4_ledger(c, s; settlement = alternative)
    @test alt["operating_cost"]==l["operating_cost"]
    @test abs(alt["cash_balance"])<1e-8
    @test any(abs(alt["actors"][i]["utility"]-l["actors"][i]["utility"])>1e-3 for i in 2:3)
    nop=r4_ledger(c, s; p2p_enabled = false)
    @test all(x["peer_export_MW"]==0 for x in nop["contracts"])
    @test nop["operating_cost"]==l["operating_cost"]
    @test abs(nop["cash_balance"])<1e-8

    # 独立验证能发现局部篡改，不能只检查总成本。
    for key in ("P_CHP", "P_D", "E", "v", "ell", "H_in", "m_pipe")
        bad=deepcopy(r)
        bad["values"][key][2][1]+=1
        @test !validate_r4_solution(c, bad)["model_pass"]
    end
    bad=deepcopy(r)
    bad["solver_objective"]+=1
    @test !validate_r4_solution(c, bad)["model_pass"]
    mktempdir() do dir
        path=save_r4_run(c, r; directory = dir, run_id = "roundtrip")
        rr=read_r4_run(path)
        @test rr.validation==r["validation"]
        @test_throws ErrorException save_r4_run(c, r; directory = dir, run_id = "roundtrip")
        @test only(compare_r4_runs([path]))["model_pass"]
        open(joinpath(path, "result.toml"), "a") do io
            write(io, "\n# altered\n")
        end
        @test_throws ErrorException read_r4_run(path)
    end

    # AG0与集中零P2P的流程不同；冻结控制逐项校核。
    ag=solve_r4_case(
        c;
        spec = R4Spec(operation = :independent),
        optimizer = R4OPT,
        enumerate_battery = true,
        budget_sec = 60,
    )
    @test length(ag["local_stages"])==2
    @test all(x["validation"]["model_pass"] for x in ag["local_stages"])
    @test ag["status"]=="network_infeasible_certified"
    @test !haskey(ag, "values")
    net_heat=sum(x["values"]["H_sell"][3]-x["values"]["H_buy"][3] for x in ag["local_stages"])
    @test net_heat>sum(PaperRebuild.r4_loss(p) for p in c.data["heat"]["pipes"])+0.1

    # 单时段无设备手算；保持损耗为零时两种方法物理等价，金额和步长可解析。
    d=deepcopy(c.data)
    d["T"]=1
    d["dt_h"]=0.5
    d["grid_price"]=[80.0]
    for x in d["actors"]
        for k in (
            "CHP_max",
            "PV_max",
            "HP_max",
            "EB_max",
            "BS_power_max",
            "BS_energy_max",
            "BS_initial",
            "flex",
            "Q_ratio",
        )
            x[k]=0.0
        end
        x["P_load"]=[x["id"]=="DSO" ? 0.0 : 0.1]
        x["H_load"]=[0.0]
        x["PV_profile"]=[0.0]
    end
    for edge in d["electric"]["edges"]
        edge["r"]=0.0
        edge["x"]=0.0
    end
    for pipe in d["heat"]["pipes"]
        pipe["U_W_mK"]=0.0
    end
    one=R4Case(d)
    analytic=solve_r4_case(one; optimizer = R4OPT, budget_sec = 60)
    independent=solve_r4_case(
        one;
        spec = R4Spec(operation = :independent),
        optimizer = R4OPT,
        budget_sec = 60,
    )
    @test analytic["validation"]["model_pass"]
    @test analytic["operating_cost"]≈8.0 atol=1e-5
    @test independent["operating_cost"]≈analytic["operating_cost"] atol=1e-5
    @test independent["validation"]["model_pass"]
    @test any(x["equation"]=="AG0_frozen" for x in independent["validation"]["rows"])
    @test !independent["ledger"]["p2p_enabled"]
    @test analytic["ledger"]["actors"][2]["utility"]≈-10 atol=1e-5
    d2=deepcopy(d)
    d2["dt_h"]=1.0
    twice=solve_r4_case(R4Case(d2); optimizer = R4OPT, budget_sec = 60)
    @test twice["operating_cost"]≈2analytic["operating_cost"] atol=1e-5

    # 可证明容量冲突：负荷下界9 MW大于所有热源最大出力1.125 MW。
    impossible=load_r4_case(joinpath(R4ROOT, "configs", "r4", "capacity_infeasible.toml"))
    upper=sum(
        x["heat_ratio"]*x["CHP_max"]+x["COP_HP"]*x["HP_max"]+x["COP_EB"]*x["EB_max"] for
        x in impossible.data["actors"]
    )
    @test upper≈1.125
    @test 10*(1-impossible.data["actors"][3]["flex"])>upper
    fail=solve_r4_case(impossible; optimizer = R4OPT, enumerate_battery = true, budget_sec = 60)
    @test fail["status"]=="infeasible_certified"
    @test !fail["validation"]["model_pass"]
    @test !haskey(fail, "values")
    timeout=solve_r4_case(c; optimizer = R4OPT, enumerate_battery = true, budget_sec = 1e-12)
    @test timeout["status"]=="time_limit_no_solution"
    @test !timeout["validation"]["model_pass"]
    missing=solve_r4_case(c; optimizer = ()->error("license unavailable"), budget_sec = 60)
    @test missing["status"]=="license_missing"
    unsupported=solve_r4_case(c; optimizer = R4OPT, budget_sec = 60)
    @test unsupported["status"]=="unsupported_solver"
    @test !haskey(unsupported, "values")
    for (term, has, status) in (
        ("TIME_LIMIT", true, "time_limit_with_incumbent"),
        ("TIME_LIMIT", false, "time_limit_no_solution"),
        ("NUMERICAL_ERROR", false, "numerical_failure"),
    )
        @test PaperRebuild.r2_status([Dict("termination"=>term)], 1, has, term=="TIME_LIMIT")==status
    end
end
