module R5CurrencyTests
using PaperRebuild, JuMP, Clarabel, Test, TOML, SHA
const PR=PaperRebuild
include(joinpath(@__DIR__, "..", "scripts", "r5_commitment_cases.jl"))
const opt=optimizer_with_attributes(
    Clarabel.Optimizer,
    "tol_feas"=>1e-10,
    "tol_gap_abs"=>1e-10,
    "tol_gap_rel"=>1e-10,
)

# 这是显式数值缩放试验，不是人民币/美元汇率，也不迁移历史文件。
function currency_case(d; factor = 1.0, currency = "CNY")
    x=deepcopy(d)
    x["schema"]="r5-dispatch-case-v2"
    x["currency"]=currency
    x["units"]["energy_price"]=currency*"/MWh"
    x["units"]["reserve_price"]=currency*"/(MW*h)"
    for g in x["devices"]
        g["cost_per_MWh"]=factor*pop!(g, "cost_USD_MWh")
    end
    x["realtime"]["penalty_per_MWh"]=factor*pop!(x["realtime"], "penalty_USD_MWh")
    x["realtime"]["price"].*=factor
    for k in ("energy_price", "up_price", "down_price")
        x["award"][k].*=factor
    end
    x
end

function currency_commitment(d; factor = 1.0)
    x=deepcopy(d)
    for s in x["scenarios"]
        s["case"]=currency_case(s["case"]; factor)
    end
    for k in keys(x["day_ahead"])
        x["day_ahead"][k].*=factor
    end
    x
end

@testset "R5 currency explicit contract and old hashes" begin
    d=r5_dispatch_hand()
    old=R5DispatchCase(d)
    @test !haskey(old.data, "currency")
    @test old.sha256==bytes2hex(sha256(PR.r5_market_text(old.data)))
    @test old.sha256==R5DispatchCase(deepcopy(d)).sha256
    v2=currency_case(d)
    for mutate in (
        x->(x["units"]["energy_price"]="USD/MWh"),
        x->(x["currency"]="EUR"),
        x->(x["devices"][1]["cost_USD_MWh"]=1.0),
        x->(x["realtime"]["penalty_USD_MWh"]=1.0),
        x->(x["award"]["origin"]="verified_market"),
    )
        x=deepcopy(v2)
        mutate(x)
        @test_throws ErrorException R5DispatchCase(x)
    end
    x=deepcopy(d)
    x["currency"]="CNY"
    @test_throws ErrorException R5DispatchCase(x)
    missing=deepcopy(v2)
    delete!(missing, "currency")
    @test_throws KeyError R5DispatchCase(missing)
    mixed=currency_commitment(r5_commitment_teaching())
    mixed["scenarios"][1]["case"]=deepcopy(r5_commitment_teaching()["scenarios"][1]["case"])
    @test_throws ErrorException R5CommitmentCase(mixed)
end

@testset "R5 currency primal dual sensitivity and frozen reread" begin
    # 完全固定的零备用手算例存在退化乘子，不能要求两次求解返回同一个次梯度。
    # 此处用既有光滑解析域：0.2 MW机组有余量，调用信号0.4/0.2。
    d=r5_dispatch_hand()
    d["devices"][2]["p_max_MW"]=0.2
    d["devices"][2]["P_initial_MW"]=0.05
    d["award"]["P_DA_MW"]=[0.112]
    d["award"]["R_up_MW"]=[0.02]
    d["award"]["R_down_MW"]=[0.02]
    d["realtime"]["alpha_up"]=[0.4]
    d["realtime"]["alpha_down"]=[0.2]
    d["realtime"]["price"]=[80.0]
    c=R5DispatchCase(d)
    usd=solve_r5_dispatch(c; optimizer = opt)
    @test usd["validation"]["optimality_pass"]
    us=PR.r5_dispatch_sensitivity(c, usd)
    @test us["kkt"]["kkt_pass"]
    for factor in (1.0, 7.0)
        cn=R5DispatchCase(currency_case(c.data; factor))
        r=solve_r5_dispatch(cn; optimizer = opt)
        @test r["validation"]["optimality_pass"]
        @test r["solver_objective"]≈factor*usd["solver_objective"] atol=1e-5
        @test all(row["unit"]=="CNY" for row in r["validation"]["rows"] if row["group"]=="cost")
        s=PR.r5_dispatch_sensitivity(cn, r)
        @test s["units"]=="CNY/MW"
        @test s["kkt"]["kkt_pass"]
        for key in keys(us["gradient"])
            @test s["gradient"][key]≈factor .* us["gradient"][key] atol=1e-5
        end
        for key in ("device_cost", "real_time_settlement", "day_ahead_cost", "delivery_penalty")
            @test r["validation"][key]≈factor*usd["validation"][key] atol=1e-5
        end
        mktempdir() do dir
            path=save_r5_dispatch_run(cn, r, joinpath(dir, "case"))
            reread=read_r5_dispatch_run(path)
            @test reread.case.sha256==cn.sha256
            @test reread.validation["optimality_pass"]
            @test reread.result["solver_objective"]==r["solver_objective"]
        end
    end
end

@testset "R5 currency shared commitment analytic and risk" begin
    for dt in (1.0, 0.25)
        d=currency_commitment(r5_commitment_teaching(; dt); factor = 7.0)
        c=R5CommitmentCase(d)
        r=solve_r5_commitment(c; optimizer = opt)
        @test r["validation"]["kkt_pass"]
        @test r["cost_optimization_complete"]
        @test r["solver_objective"]≈7*2.085dt atol=1e-5
        for (k, v) in (("P_DA_MW", 0.08), ("R_up_MW", 0.08), ("R_down_MW", 0.062))
            @test only(r["first_stage"][k])≈v atol=1e-7
        end
        mktempdir() do dir
            path=save_r5_commitment_run(c, r, joinpath(dir, "case"))
            @test read_r5_commitment_run(path).validation["kkt_pass"]
        end
    end
    d=TOML.parsefile(joinpath(@__DIR__, "..", "configs", "r5", "risk", "thermal_e030_r005.toml"))
    d["commitment"]=currency_commitment(d["commitment"]; factor = 7.0)
    c=R5RiskCase(d)
    r=solve_r5_risk(c; optimizer = opt, method = :enumeration, budget_sec = 60.0)
    @test r["status"]=="enumeration_complete"
    @test r["validation"]["risk_pass"]
    @test r["cost_optimization_complete"]
    @test r["validation"]["worst_net_cost"]≈7*1.36648 atol=1e-5
    @test r["validation"]["worst_violation_probability"]<=0.3+1e-6
    # 条件子问题的费用割也必须保留显式币种，不能留下USD标签。
    stage=Dict("P_DA_MW"=>[0.08], "R_up_MW"=>[0.08], "R_down_MW"=>[0.062])
    sub=solve_r5_benders_subproblem(c, 1, stage; optimizer = opt)
    @test sub["validation"]["kkt_pass"]
    @test sub["validation"]["physical_dispatch_pass"]
    cut=r5_benders_cut(c, sub)
    @test cut["units"]=="synthetic_CNY"
    @test cut["source_value"]<=sub["solver_objective"]+1e-7
    mktempdir() do dir
        path=save_r5_risk_run(c, r, joinpath(dir, "case"))
        @test read_r5_risk_run(path).validation["risk_pass"]
    end
end
end
