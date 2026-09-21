module R9RiskTests
using PaperRebuild, Test, TOML, JuMP, Clarabel
const PR=PaperRebuild
const ROOT=normpath(joinpath(@__DIR__, ".."))

@testset "R9-RK protocol and training-only physical mapping" begin
    spec=load_r9_reserve_study(joinpath(ROOT, "configs/r9/reserve-study.toml"))
    p=TOML.parsefile(joinpath(ROOT, "configs/r9/reserve-trajectories.toml"))
    p["samples"]["train"]=120
    protocol=R6Protocol(p)
    train=r6_generate_trajectories(protocol, "train")
    reps=r6_fit_representatives(train, protocol)
    @test reps["converged"]
    template=r9_reserve_template(
        joinpath(ROOT, "docs/reading/ch07"),
        joinpath(ROOT, "configs/r9/reserve-protocol.toml"),
    )
    oldhash=template.sha256
    cases=[
        r9_reserve_risk_case(template, train, reps, spec, s; pilot = true) for
        s in ("3A", "3B", "3C")
    ]
    @test template.sha256==oldhash
    @test template.data["realtime"]["delta"]==0.1
    @test train.sha256==r6_generate_trajectories(protocol, "train").sha256
    for (scheme, c) in zip(("3A", "3B", "3C"), cases)
        x=c.data
        @test x["r9_study"]["pilot"] && !x["r9_study"]["continuous_call_guarantee"]
        @test x["r9_study"]["delta_override"]==Dict("from"=>0.1, "to"=>0.0)
        @test x["r9_study"]["template_sha256"]==oldhash
        @test length(x["commitment"]["scenarios"])==4
        @test x["epsilon"]==(scheme=="3A" ? 0.0 : 0.05)
        @test all(
            x["commitment"]["day_ahead"][k]==template.data["award"][k] for
            k in ("energy_price", "up_price", "down_price")
        )
        for (j, s) in enumerate(x["commitment"]["scenarios"])
            i=reps["representative_indices"][j]
            d=s["case"]
            @test s["probability"]≈reps["counts"][j]/sum(reps["counts"][1:4])
            @test d["electric"]==template.data["electric"] && d["heat"]==template.data["heat"]
            @test d["buildings"]==template.data["buildings"] &&
                  d["ambient_K"]==template.data["ambient_K"]
            @test d["realtime"]["delta"]==0 && d["currency"]=="CNY"
            @test d["realtime"]["alpha_up"]-d["realtime"]["alpha_down"]==train.values[2, :, i]
            @test all(d["realtime"]["alpha_up"] .* d["realtime"]["alpha_down"] .== 0)
            for a in d["devices"]
                a["kind"]=="PV" || continue
                @test a["available_MW"]==a["p_max_MW"] .* train.values[1, :, i]
            end
        end
    end
    @test cases[1].data["ambiguity"]["radius"]==maximum(
        PR.r5_market_array(cases[1].data["ambiguity"]["distance"]),
    )
    @test cases[2].data["ambiguity"]["radius"]==0
    @test cases[3].data["ambiguity"]["radius"]==spec.data["radius"]
    for c in cases[2:3]
        a, b=deepcopy(cases[1].data["commitment"]), deepcopy(c.data["commitment"])
        delete!(a, "name")
        delete!(b, "name")
        @test a==b
    end
    full=r9_reserve_risk_case(template, train, reps, spec, "3C")
    # 保留原性能采样身份，用其冻结来源重建；7.5来源更正不重写已存7.4风险输入。
    frozen_template=r9_reserve_template(
        joinpath(ROOT, "results/summaries/r9-inputs-20260920-v1"),
        joinpath(ROOT, "configs/r9/reserve-protocol.toml"),
    )
    frozen_full=r9_reserve_risk_case(frozen_template, train, reps, spec, "3C")
    @test frozen_full.sha256=="c8fda7079f341bf7fa87dd8095039f8403a9811d39c4a15b9ca5d9b6d6acfab4"
    actual, expected=deepcopy(full.data), deepcopy(frozen_full.data)
    @test actual["r9_study"]["template_sha256"]==template.sha256!=frozen_template.sha256
    actual["r9_study"]["template_sha256"]=frozen_template.sha256
    for (a, b) in zip(actual["commitment"]["scenarios"], expected["commitment"]["scenarios"])
        # 情景身份包含来源哈希；先按完整数据核验两边，再只归一化比较副本的身份。
        @test a["case_sha256"]==R5DispatchCase(a["case"]).sha256
        @test b["case_sha256"]==R5DispatchCase(b["case"]).sha256
        @test a["case_sha256"]!=b["case_sha256"]
        a["case_sha256"]=b["case_sha256"]
        sa=pop!(a["case"]["r9_reserve"], "source_hashes")
        sb=pop!(b["case"]["r9_reserve"], "source_hashes")
        @test Set(keys(sa))==Set(keys(sb))
        @test Set(k for k in keys(sa) if sa[k]!=sb[k])==Set(["inputs.toml"])
    end
    @test actual==expected # 100情景、设备、概率、风险半径及所有物理和费用数值逐值相同。
    @test !full.data["r9_study"]["pilot"]
    @test length(full.data["commitment"]["scenarios"])==100
    @test [s["probability"] for s in full.data["commitment"]["scenarios"]]==reps["counts"] ./ 120
    @test_throws ErrorException r9_reserve_risk_case(
        template,
        r6_generate_trajectories(protocol, "validation"),
        reps,
        spec,
        "3B",
    )
    @test_throws ErrorException r9_reserve_risk_case(template, train, reps, spec, "other")
    changed=deepcopy(reps)
    changed["probabilities"][1]+=0.01
    @test_throws ErrorException r9_reserve_risk_case(template, train, changed, spec, "3B")
    for mutate in (
        x->(x["delivery_delta"]=0.1),
        x->(x["radius"]=-1),
        x->(x["epsilon"]=0.1),
        x->(x["currency"]="USD"),
    )
        d=deepcopy(spec.data)
        mutate(d)
        @test_throws ErrorException R9ReserveStudySpec(d)
    end
end

@testset "R9-RK finite-support robust and empirical limiting cases" begin
    p=[0.2, 0.3, 0.5]
    D=[0.0 0.25 0.5; 0.25 0.0 0.25; 0.5 0.25 0.0]
    cost=[4.0, 1.0, 8.0]
    opt=optimizer_with_attributes(
        Clarabel.Optimizer,
        "tol_feas"=>1e-10,
        "tol_gap_abs"=>1e-10,
        "tol_gap_rel"=>1e-10,
    )
    for (rho, expected) in ((0.0, sum(p .* cost)), (maximum(D), maximum(cost)))
        r=r5_worst_distribution(p, D, cost, rho; optimizer = opt)
        @test r["validation"]["pass"]
        @test r["validation"]["dual_value"]≈expected atol=1e-7
    end
    # 给任一支持点正质量且epsilon=0时，不可能释放该点的舒适界。
    for mask in ([1.0, 0, 0], [0.0, 1, 0], [0.0, 0, 1])
        r=r5_worst_distribution(p, D, mask, maximum(D); optimizer = opt, quantity = :probability)
        @test r["validation"]["pass"]
        @test r["validation"]["dual_value"]≈1 atol=1e-8
    end
end
end
