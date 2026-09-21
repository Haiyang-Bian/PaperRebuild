using Test, PaperRebuild, JuMP, HiGHS, TOML, SHA

@testset "R7 explicit monetary versions and unchanged physical handoff" begin
    root=normpath(joinpath(@__DIR__, ".."))
    legacy=load_r7_normal_case(joinpath(root, "configs/r7/normal-hand.toml"))
    original=deepcopy(legacy.data)
    opt=optimizer_with_attributes(
        HiGHS.Optimizer,
        "threads"=>1,
        "primal_feasibility_tolerance"=>1e-9,
        "dual_feasibility_tolerance"=>1e-9,
        "mip_feasibility_tolerance"=>1e-9,
        "mip_rel_gap"=>1e-9,
    )
    # 两种合成计价设计；这里无汇率语义，也不把旧论文输入重新标注为CNY。
    function input_v2(currency = "CNY"; scale = 1.0)
        d=deepcopy(original)
        d["schema"]="r7-normal-case-v2"
        d["name"]="synthetic_currency_hand_"*currency
        d["currency"]=currency
        d["units"]["price"]=currency*"/MWh"
        d["electric"]["price_MWh"]=scale .* pop!(d["electric"], "price_USD_MWh")
        for g in d["devices"]
            g["cost_P_MWh"]=scale*pop!(g, "cost_P_USD_MWh")
            g["kind"]=="CHP" && (g["startup_cost"]=scale*pop!(g, "startup_cost_USD"))
        end
        d
    end
    c=R7NormalCase(input_v2())
    old=solve_r7_normal(legacy; optimizer = opt)
    r=solve_r7_normal(c; optimizer = opt)
    @test old["candidate_accepted"] && old["conditional_cost_complete"]
    @test old["schema"]=="r7-normal-result-v1" && !haskey(old, "currency")
    @test old["solver_objective_USD"]≈118.4 atol=1e-6
    @test r["candidate_accepted"] && r["conditional_cost_complete"]
    @test r["schema"]=="r7-normal-result-v2" && r["currency"]=="CNY"
    @test r["objective_kind"]=="expected_normal_cost_CNY"
    @test r["solver_objective"]≈118.4 atol=1e-6
    @test r["validation"]["resource_cost"]≈50.4 atol=1e-6
    @test r["validation"]["grid_payment"]≈68.0 atol=1e-6
    @test r["validation"]["currency"]=="CNY"
    @test !any(occursin("_USD", k) for k in keys(r))
    @test !any(occursin("_USD", k) for k in keys(r["validation"]))
    @test last(r["validation"]["rows"])["unit"]=="CNY"
    @test legacy.data==original && legacy.sha256==PaperRebuild.r7_digest(original)
    @test !haskey(legacy.data, "currency") && c.sha256!=legacy.sha256
    # 同一物理调度可在两种等系数计价设计下回代，不能由费用变化隐式改动控制。
    mapped=deepcopy(old)
    mapped["schema"]="r7-normal-result-v2"
    mapped["currency"]="CNY"
    mapped["case_sha256"]=c.sha256
    mapped["objective_kind"]="expected_normal_cost_CNY"
    mapped["solver_objective"]=pop!(mapped, "solver_objective_USD")
    mapped["lower_bound"]=pop!(mapped, "lower_bound_USD")
    @test validate_r7_normal(c, mapped)["model_pass"]
    scaled=R7NormalCase(input_v2(; scale = 1000.0))
    rr=solve_r7_normal(scaled; optimizer = opt)
    @test rr["candidate_accepted"] && rr["conditional_cost_complete"]
    @test rr["solver_objective"]≈118400.0 atol=1e-4
    usd=R7NormalCase(input_v2("USD"))
    zero=solve_r7_normal(usd; optimizer = opt, budget_sec = 0)
    @test zero["status"]=="budget_exhausted" && zero["currency"]=="USD"
    @test !haskey(zero, "values") && !zero["candidate_accepted"]

    @testset "R9-RC1 startup is per event, operation integrates time" begin
        for dt in (1.0, 0.5)
            d=deepcopy(PaperRebuild.r7_normal_chp(c.data, c.data["devices"][1]).data)
            d["dt_h"]=dt
            d["previous_commitment"]=0
            d["previous_duration_h"]=3.0
            d["previous_P_MW"]=zeros(length(d["probabilities"]))
            spec=R7CHPSpec(d)
            m=Model(opt)
            b=add_r7_chp_commitment!(m, spec; fixed_u = ones(Int, 4))
            for p in b.variables["P_CHP"]
                fix(p, 0.4; force = true)
            end
            @objective(m, Min, b.cost)
            set_silent(m)
            set_time_limit_sec(m, 20.0)
            optimize!(m)
            @test termination_status(m)==MOI.OPTIMAL
            v=Dict(k=>Array(value.(a)) for (k, a) in b.variables)
            q=validate_r7_chp(spec, v)
            @test q["component_pass"] && q["currency"]=="CNY"
            @test q["startup_cost"]≈30.0 atol=1e-7
            @test q["running_cost"]≈32.0dt atol=1e-7
            @test objective_value(m)≈30.0+32.0dt atol=1e-7
            @test q["total_cost"]≈objective_value(m) atol=1e-7
        end
    end

    @testset "R9-RC2 state inheritance keeps units and parent identity" begin
        e=r7_normal_event(
            c,
            r;
            event_start = 2,
            periods = 2,
            renewable_factor = 0.4,
            loss_limit_MWh = 2.0,
        )
        @test e.case.data["currency"]==e.evidence["currency"]=="CNY"
        @test e.case.data["units"]["price"]=="CNY/MWh"
        @test !haskey(e.case.data["electric"], "price_MWh")
        @test !haskey(e.case.data["electric"], "price_USD_MWh")
        @test e.evidence["parent_case_sha256"]==c.sha256
        @test e.case.data["devices"][2]["initial_MWh"]≈PaperRebuild.r7_unpack(r["values"], "E_BES")[
            2,
            2,
            :,
        ]
        @test e.case.data["devices"][1]["previous_P_MW"]≈PaperRebuild.r7_unpack(r["values"], "P")[
            1,
            1,
            :,
        ]
        @test e.case.data["dt_h"]==1.0 && e.case.data["periods"]==2
    end

    @testset "Reject ambiguous money" begin
        for mutate in (
            d->delete!(d, "currency"),
            d->(d["schema"]="r7-normal-case-v1"),
            d->(d["currency"]="EUR"),
            d->(d["units"]["price"]="USD/MWh"),
            d->(d["electric"]["price_USD_MWh"]=d["electric"]["price_MWh"]),
            d->(d["devices"][1]["cost_P_USD_MWh"]=20.0),
            d->(d["devices"][1]["startup_cost_USD"]=30.0),
            d->(d["devices"][1]["cost_P_MWh"]=-1.0),
        )
            d=input_v2()
            mutate(d)
            @test_throws ErrorException R7NormalCase(d)
        end
        for mutate in (
            x->(x["currency"]="USD"),
            x->delete!(x, "currency"),
            x->(x["schema"]="r7-normal-result-v1"),
            x->(x["solver_objective_USD"]=x["solver_objective"]),
        )
            x=deepcopy(r)
            mutate(x)
            @test_throws ErrorException validate_r7_normal(c, x)
        end
    end
    @testset "Portable v2 replay and tamper rejection" begin
        parent=mktempdir(joinpath(root, "tmp"); cleanup = false)
        path=joinpath(parent, "normal-CNY")
        save_r7_normal(c, r, path)
        x=read_r7_normal(path)
        @test x.case.sha256==c.sha256 && x.validation["model_pass"]
        @test x.result["currency"]=="CNY"
        @test x.validation["cost"]≈118.4 atol=1e-6
        meta=TOML.parsefile(joinpath(path, "metadata.toml"))
        @test meta["schema"]=="r7-normal-metadata-v2" && meta["currency"]=="CNY"
        @test_throws ErrorException save_r7_normal(c, r, path)
        relocated=joinpath(parent, "relocated")
        cp(path, relocated)
        replay=joinpath(relocated, "code", "replay.jl")
        project="--project="*root
        output=read(`$(Base.julia_cmd()) --startup-file=no $project $replay`, String)
        @test occursin("model=true", output)
        open(joinpath(relocated, "result.toml"), "a") do io
            write(io, "\n# tamper witness\n")
        end
        @test_throws ErrorException read_r7_normal(relocated)
        println("Currency replay evidence preserved: ", relpath(parent, root))
    end
end
