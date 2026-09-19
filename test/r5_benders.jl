module R5BendersTests
using Test, PaperRebuild, JuMP, HiGHS, Clarabel, TOML

const root=normpath(joinpath(@__DIR__, "..", "configs", "r5", "risk"))
const highs=optimizer_with_attributes(
    HiGHS.Optimizer,
    "primal_feasibility_tolerance"=>1e-9,
    "dual_feasibility_tolerance"=>1e-9,
)
const clar=optimizer_with_attributes(
    Clarabel.Optimizer,
    "tol_feas"=>1e-10,
    "tol_gap_abs"=>1e-10,
    "tol_gap_rel"=>1e-10,
)
stage(P = 0.08, U = 0.08, D = 0.062) = Dict("P_DA_MW"=>[P], "R_up_MW"=>[U], "R_down_MW"=>[D])

@testset "R5-BD finite input bounds and parameter rows" begin
    c=load_r5_risk_case(joinpath(root, "hard_zero.toml"))
    hashes=deepcopy(c.data)
    @test R5BendersSpec().feasibility==:cuts
    @test_throws ErrorException R5BendersSpec(feasibility = :unknown)
    @test_throws ErrorException R5BendersSpec(max_iterations = 201)
    @test_throws ErrorException R5BendersSpec(relative_gap = 0.1)
    @test PaperRebuild.r5_benders_spec(PaperRebuild.r5_benders_spec(R5BendersSpec())).max_iterations==200
    for s in 1:3
        bd=r5_benders_bounds(c, s)
        @test all(isfinite(l)&&isfinite(u)&&l<=u for (l, u) in values(bd.box))
        @test bd.lower_cost<0
        @test bd.box["delivery/1/1"]==(-1.0, 1.0)
        @test bd.box["mismatch/1/1"]==(0.0, 0.0)
        sys=PaperRebuild.r5_benders_system(c, s, stage(), 0)
        old=PaperRebuild.r5_dispatch_dual_system(sys.view)
        xf=PaperRebuild.r5_benders_flat(stage())
        @test all(
            PaperRebuild.r5_benders_rhs_value(sys.rows[id], xf)≈row.rhs for (id, row) in old.rows
        )
    end
    @test c.data==hashes
    b=build_r5_benders_subproblem(c, 1, stage())
    @test b.model_type=="continuous_LP"&&termination_status(b.model)==MOI.OPTIMIZE_NOT_CALLED
    @test_throws ErrorException build_r5_benders_subproblem(c, 0, stage())
    @test_throws ErrorException build_r5_benders_subproblem(c, 1, stage(); branch = 2)
    @test_throws ErrorException build_r5_benders_subproblem(c, 1, stage(NaN))
    for name in ("quarter", "future_e030_r005"), s in 1:3
        cc=load_r5_risk_case(joinpath(root, name*".toml"))
        bd=r5_benders_bounds(cc, s)
        @test all(isfinite(l)&&isfinite(u)&&l<=u for (l, u) in values(bd.box))
        x=Dict(
            k=>cc.data["commitment"]["bounds"][k]["lower"] for k in PaperRebuild.R5_COMMITMENT_KEYS
        )
        sys=PaperRebuild.r5_benders_system(cc, s, x, 0)
        old=PaperRebuild.r5_dispatch_dual_system(sys.view)
        xf=PaperRebuild.r5_benders_flat(x)
        @test all(
            PaperRebuild.r5_benders_rhs_value(sys.rows[id], xf)≈row.rhs for (id, row) in old.rows
        )
    end
end

@testset "R5-BD recourse KKT and conditional cuts" begin
    c=load_r5_risk_case(joinpath(root, "hard_zero.toml"))
    for opt in (highs, clar), s in 1:3
        r=solve_r5_benders_subproblem(c, s, stage(); optimizer = opt)
        @test r["status"]=="solver_optimal"
        @test r["validation"]["kkt_pass"]
        @test r["validation"]["physical_dispatch_pass"]
        cut=r5_benders_cut(c, r)
        @test cut["source_value"]<=r["solver_objective"]+1e-7
        @test cut["source_value"]>=r["solver_objective"]-1e-3
        @test cut["deactivation_M"]>=0
        # 盒内包括不是物理可行的承诺；不匹配分支的割必须对整个盒冗余。
        bd=r5_benders_bounds(c, s)
        _, hi=PaperRebuild.r5_benders_range(
            cut["gradient"],
            bd.first_stage_box;
            constant = cut["constant"],
        )
        @test hi-cut["deactivation_M"]<=bd.lower_cost+1e-7
        @test all(bd.box[k][1]-1e-7<=v<=bd.box[k][2]+1e-7 for (k, v) in r["flat_values"])
        stored=TOML.parse(PaperRebuild.r5_market_text(r))
        @test validate_r5_benders_subproblem(c, stored)["kkt_pass"]
        bad=deepcopy(r)
        empty!(bad["raw_duals"])
        @test !validate_r5_benders_subproblem(c, bad)["kkt_pass"]
        @test_throws ErrorException r5_benders_cut(c, bad)
        bad=deepcopy(r)
        bad["flat_values"]["P_PCC/1/1"]+=0.01
        @test !validate_r5_benders_subproblem(c, bad)["kkt_pass"]
        bad=deepcopy(r)
        bad["source_unchanged"]=false
        @test_throws ErrorException r5_benders_cut(c, bad)
    end
    @test_throws ErrorException solve_r5_benders_subproblem(
        c,
        1,
        stage();
        optimizer = highs,
        budget_sec = -1,
    )
    tiny=solve_r5_benders_subproblem(c, 1, stage(); optimizer = highs, budget_sec = 1e-12)
    @test tiny["status"]=="budget_exhausted_before_solve"&&!tiny["has_candidate"]
    no=solve_r5_benders_subproblem(c, 1, stage(); optimizer = ()->error("license unavailable"))
    @test no["status"]=="license_unavailable"&&!no["validation"]["kkt_pass"]
end

@testset "R5-BD elastic feasibility and hard physical boundary" begin
    c=load_r5_risk_case(joinpath(root, "hard_zero.toml"))
    # 高购电超过负荷/电锅炉的吸收能力。零购电可由GT供能，并非不可行反例。
    x=stage(0.9, 0, 0)
    cost=solve_r5_benders_subproblem(c, 1, x; optimizer = highs)
    @test cost["status"]=="solver_infeasible"
    phase=solve_r5_benders_subproblem(c, 1, x; optimizer = highs, elastic = true)
    @test phase["validation"]["kkt_pass"]
    @test !phase["validation"]["physical_dispatch_pass"]
    @test phase["solver_objective"]>0
    cut=r5_benders_cut(c, phase)
    @test cut["productive"]&&cut["source_value"]>0
    feasible=PaperRebuild.r5_benders_flat(stage())
    @test cut["constant"]+sum(a*feasible[k] for (k, a) in cut["gradient"])<=1e-7
    zero=solve_r5_benders_subproblem(c, 1, stage(); optimizer = highs, elastic = true)
    @test zero["validation"]["kkt_pass"]
    @test zero["solver_objective"]≈0 atol=1e-8
    @test !r5_benders_cut(c, zero)["productive"]
end

@testset "R5-BD signed multipliers and bounded numerical guards" begin
    row(a, s, b, B = Dict{String,Float64}()) = (;
        coefficients = Dict("y"=>Float64(a)),
        sense = s,
        rhs = Float64(b),
        parameters = B,
        bound = isempty(B),
    )
    sys=(;
        rows = Dict(
            "parameter"=>row(1, :ge, 0, Dict("x"=>1.0)),
            "lower"=>row(1, :ge, -2),
            "upper"=>row(1, :le, 2),
        ),
        cost = Dict("y"=>1.0),
        box = Dict("y"=>(-2.0, 2.0)),
        xb = Dict("x"=>(-1.0, 1.0)),
        variable_scales = Dict("y"=>2.0),
        money_scale = 1.0,
    )
    λ=Dict("parameter"=>1.0, "lower"=>0.0, "upper"=>0.0)
    check=PaperRebuild.r5_benders_lp_check(sys, Dict("x"=>0.5), Dict("y"=>0.5), λ, 0.5)
    @test check["kkt_pass"]
    noisy=copy(λ)
    noisy["parameter"]+=1e-8
    noisy["upper"]=1e-10
    keep=copy(noisy)
    cut=PaperRebuild.r5_benders_minorant(sys, noisy)
    @test noisy==keep
    @test cut["stationarity_guard"]>0&&cut["sign_guard"]>0
    for x in range(-1, 1; length = 9), y in range(x, 2; length = 7)
        @test cut["constant"]+cut["gradient"]["x"]*x<=y
    end
    bad=copy(λ)
    bad["parameter"]=-1
    @test !PaperRebuild.r5_benders_lp_check(sys, Dict("x"=>0.5), Dict("y"=>0.5), bad, 0.5)["kkt_pass"]
    eqsys=merge(sys, (; rows = Dict("eq"=>row(1, :eq, 0, Dict("x"=>1.0)))))
    @test PaperRebuild.r5_benders_lp_check(
        eqsys,
        Dict("x"=>0.5),
        Dict("y"=>0.5),
        Dict("eq"=>1.0),
        0.5,
    )["kkt_pass"]
    upper=merge(sys, (; cost = Dict("y"=>-2.0)))
    @test PaperRebuild.r5_benders_lp_check(
        upper,
        Dict("x"=>0.5),
        Dict("y"=>2.0),
        Dict("parameter"=>0.0, "lower"=>0.0, "upper"=>-2.0),
        -4.0,
    )["kkt_pass"]
    fixed=merge(sys, (; rows = Dict("lower"=>row(1, :ge, 0), "upper"=>row(1, :le, 0))))
    @test PaperRebuild.r5_benders_lp_check(
        fixed,
        Dict("x"=>0.5),
        Dict("y"=>0.0),
        Dict("lower"=>2.0, "upper"=>-1.0),
        0.0,
    )["kkt_pass"]
end

@testset "R5-BD negative recourse zero weights and independent differences" begin
    c=load_r5_risk_case(joinpath(root, "hard_zero.toml"))
    # 费用上界/下界来自声明输入，实时价600使上调用补救确实为负。
    d=deepcopy(c.data)
    for s in d["commitment"]["scenarios"]
        s["case"]["realtime"]["price"].=600.0
    end
    negative=R5RiskCase(d)
    r=solve_r5_benders_subproblem(negative, 2, stage(); optimizer = highs)
    @test r["validation"]["kkt_pass"]&&r["solver_objective"]<0
    cut=r5_benders_cut(negative, r)
    @test cut["source_value"]<0&&cut["lower_cost"]<r["solver_objective"]
    zero=load_r5_risk_case(joinpath(root, "hard_r100.toml"))
    # ρ=1的费用对手可给其他情景零权重；独立补救仍逐个产生有限证书，不除概率。
    for s in 1:3
        q=solve_r5_benders_subproblem(zero, s, stage(0.062, 0.062, 0.08); optimizer = highs)
        @test q["validation"]["kkt_pass"]
        @test all(isfinite, values(r5_benders_cut(zero, q)["gradient"]))
    end
    # 非零容量误差预算：来自5-4的导数必须保留，不能只对调用量求导。
    d=deepcopy(c.data)
    for s in d["commitment"]["scenarios"]
        s["case"]["devices"][2]["cost_USD_MWh"]=2000.0
        s["case"]["realtime"]["delta"]=0.1
    end
    budget_case=R5RiskCase(d)
    for (cc, s, x, elastic) in (
        (c, 2, stage(0.08, 0.06, 0.04), false),
        (budget_case, 2, stage(0.142, 0.04, 0.02), false),
        (c, 1, stage(0.9, 0, 0), true),
    )
        base=solve_r5_benders_subproblem(cc, s, x; optimizer = highs, elastic)
        @test base["validation"]["kkt_pass"]
        g=r5_benders_cut(cc, base)["gradient"]
        if cc===budget_case
            @test g["R_up_MW/1"]≈1828 atol=1e-4
            @test g["R_down_MW/1"]≈-92 atol=1e-4
        end
        for key in (elastic ? ("P_DA_MW",) : PaperRebuild.R5_COMMITMENT_KEYS),
            h in (1e-3, 1e-4, 1e-5)

            objective=Float64[]
            for sign in (-1, 1)
                trial=deepcopy(x)
                trial[key][1]+=sign*h
                rr=solve_r5_benders_subproblem(cc, s, trial; optimizer = highs, elastic)
                @test rr["validation"]["kkt_pass"]
                push!(objective, rr["solver_objective"])
            end
            fd=(objective[2]-objective[1])/(2h)
            @test abs(fd-g["$key/1"])/max(1.0, abs(fd), abs(g["$key/1"]))<=1e-3
        end
    end
    # 舒适放松与严格物理域分开，分支0的割不能强加给分支1。
    thermal=load_r5_risk_case(joinpath(root, "thermal_e030_r005.toml"))
    x=stage(0.08, 0.08, 0.07478)
    strict=solve_r5_benders_subproblem(thermal, 3, x; optimizer = highs, branch = 0)
    relaxed=solve_r5_benders_subproblem(thermal, 3, x; optimizer = clar, branch = 1)
    @test strict["status"]=="solver_infeasible"
    @test relaxed["validation"]["kkt_pass"]
    diag=solve_r5_benders_subproblem(thermal, 3, x; optimizer = clar, elastic = true, branch = 0)
    @test diag["validation"]["kkt_pass"]
    @test r5_benders_cut(thermal, diag)["productive"]
end
end
