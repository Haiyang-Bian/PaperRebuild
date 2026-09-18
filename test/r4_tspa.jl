using Test, JuMP, Clarabel, TOML

@testset "R4 TSPA network disagreement and penalty accounting" begin
    root=normpath(joinpath(@__DIR__, ".."))
    c=load_r4_case(joinpath(root, "configs", "r4", "baseline", "import_flexible.toml"))
    opt=optimizer_with_attributes(
        Clarabel.Optimizer,
        "tol_feas"=>1e-9,
        "tol_gap_abs"=>1e-9,
        "tol_gap_rel"=>1e-9,
    )
    @test_throws ErrorException R4TSPASpec(penalty = 0)
    @test_throws ErrorException R4TSPASpec(penalty = NaN)
    @test_throws ErrorException R4TSPASpec(weight_rule = :invented)
    @test_throws ErrorException build_r4_model(c; balance_penalty = 100)
    b=build_r4_model(c; stage = :trading, modes = [0, 1, 0, 1])
    @test b.model_class=="SOCP"
    @test !haskey(b.variables, "P_grid")
    @test haskey(b.variables, "P_peer")
    @test termination_status(b.model)==MOI.OPTIMIZE_NOT_CALLED
    ag=solve_r4_case(
        c;
        optimizer = opt,
        spec = R4Spec(operation = :independent),
        enumerate_battery = true,
        budget_sec = 60,
    )
    sw=solve_r4_case(c; optimizer = opt, enumerate_battery = true, budget_sec = 60)
    before=deepcopy((ag, sw))
    r=solve_r4_tspa(
        c;
        independent = ag,
        central = sw,
        optimizer = opt,
        enumerate_battery = true,
        budget_sec = 60,
    )
    @test (ag, sw)==before
    @test r["validation"]["record_pass"]
    @test r["validation"]["trading_model_pass"]
    @test r["validation"]["strict_network_physical_pass"]
    @test r["validation"]["relaxed_network_pass"]
    @test r["validation"]["stage1_allocation_pass"]
    @test !r["trading_selected"]["validation"]["network_checked"]
    @test length(r["economics"]["stage2"])==2
    @test all(x["validation"]["allocation_pass"] for x in r["economics"]["stage2"])
    @test !r["economics"]["coalition_core_certified"]
    @test maximum(abs, r["trading_selected"]["values"]["P_peer"])<1e-5
    a, b=r["economics"]["stage2"]
    @test b["allocation"]["surplus"]-a["allocation"]["surplus"]≈b["penalty_cost"] atol=1e-8
    frozen=PaperRebuild.r4_tspa_frozen(r["trading_selected"])
    for key in ("slack_P_pos", "slack_Q_neg", "slack_H_pos", "slack_m_neg")
        bad=deepcopy(r["elastic_network"])
        bad["values"][key][2][1]+=0.01
        @test !validate_r4_elastic(c, bad; frozen)["relaxed_model_pass"]
    end
    bad=deepcopy(r["elastic_network"])
    bad["values"]["P_D"][2][1]+=0.01
    @test !validate_r4_elastic(c, bad; frozen)["relaxed_model_pass"]
    bad=deepcopy(r["trading_selected"])
    bad["values"]["H_peer"][1]+=0.01
    @test !validate_r4_trading(c, bad)["model_pass"]
    bad=deepcopy(r)
    bad["economics"]["stage2"][1]["resource_surplus"]+=1
    @test_throws ErrorException validate_r4_tspa(c, bad)
    mktempdir() do dir
        path=save_r4_tspa_run(c, r; directory = dir, run_id = "tspa")
        @test read_r4_tspa_run(path).validation==r["validation"]
        @test_throws ErrorException save_r4_tspa_run(c, r; directory = dir, run_id = "tspa")
        open(joinpath(path, "result.toml"), "a") do io
            write(io, "\n# altered\n")
        end
        @test_throws ErrorException read_r4_tspa_run(path)
    end
    # 低罚系数允许选择人为漏供，不将其负剩余或松弛解判为实际成功。
    low=solve_r4_tspa(
        c;
        independent = ag,
        central = sw,
        optimizer = opt,
        enumerate_battery = true,
        spec = R4TSPASpec(penalty = 1.0),
        budget_sec = 60,
        trading_run = r["trading_selected"],
    )
    @test low["validation"]["record_pass"]
    @test low["validation"]["relaxed_network_pass"]
    @test !low["validation"]["relaxed_point_physical_pass"]
    @test low["elastic_network"]["validation"]["penalty_cost"]>0.1
    @test low["trading_selected"]["values"]==r["trading_selected"]["values"]
    @test_throws ErrorException solve_r4_tspa(
        c;
        independent = ag,
        central = sw,
        optimizer = opt,
        budget_sec = 0,
    )
    # 预算耗尽与求解器缺失仍保留可嵌入AG0，不能伪造弹性网络或阶段II成功。
    timed=solve_r4_tspa(c; independent = ag, central = sw, optimizer = opt, budget_sec = 1e-8)
    @test timed["validation"]["record_pass"]
    @test !timed["validation"]["relaxed_network_pass"]
    @test isempty(timed["economics"]["stage2"])
    absent=solve_r4_tspa(
        c;
        independent = ag,
        central = sw,
        optimizer = ()->error("license missing"),
        budget_sec = 60,
    )
    @test absent["trading_solver"]["status"]=="license_missing"
    @test absent["validation"]["record_pass"]
    @test !absent["validation"]["relaxed_network_pass"]
    # 原文(4-102)须有非负第二阶段剩余；扣罚改变分歧点，不能创造真实资源收益。
    excl=r4_nash_allocation([5.0, 10.0, 10.0], [20.0, 5.0, 5.0], [2.0, 1.0, 1.0])
    incl=r4_nash_allocation([5.0, 10.0, 10.0], [12.0, 5.0, 5.0], [2.0, 1.0, 1.0])
    @test excl["surplus"]==-5.0
    @test !validate_r4_allocation(excl)["allocation_pass"]
    @test incl["surplus"]==3.0
    @test validate_r4_allocation(incl)["allocation_pass"]
    @test incl["surplus"]-excl["surplus"]==8.0
    # 两倍时长仅改变积分，不改变罚项的输入容量尺度。
    dd=deepcopy(c.data)
    dd["dt_h"]*=2
    @test r4_tspa_scales(R4Case(dd))==r4_tspa_scales(c)
    # 只松弛节点平衡不能救活冻结负荷与硬边界自身的冲突。
    hard=deepcopy(frozen)
    hard[1]["values"]["P_D"][2][1]+=1.0
    failed=PaperRebuild.r4_solve_stage(
        c,
        R4Spec(),
        opt,
        time()+60;
        stage = :network,
        frozen = hard,
        enumerate_battery = true,
        build_options = (balance_penalty = 10000.0,),
    )
    @test failed["status"]=="infeasible_certified"
    @test !haskey(failed, "values")
end
