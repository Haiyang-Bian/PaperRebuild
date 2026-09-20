using Test, PaperRebuild, TOML, CSV
include("r7_flow_planning_study.jl")
length(ARGS) in (1, 2) ||
    error("usage: check_r7_lossy_flow_results.jl REPORT [OLD_LOSSLESS_REPORT]")
report=abspath(first(ARGS))
joint_check(report)
items, rule=joint_inputs(report)
rows=collect(CSV.File(joinpath(report, "summary.csv")))
@testset "R7-H5 frozen lossy controls, battery domain and original values" begin
    @test length(items)==length(rows)==rule["record_count"]==24
    @test rule["origin"]=="synthetic"
    @test Set(x.id for x in rows)==Set(x["id"] for x in items)
    for group in rule["groups"], UA in rule["UA_values_W_K"]
        cases=filter(x->x["safety_group"]==group&&x["UA_W_K"]==UA, items)
        @test length(cases)==4
        @test length(unique(x["case_sha256"] for x in cases))==1
        fixed=filter(x->x["control"]=="prescribed", cases)
        @test length(unique(x["spec_sha256"] for x in fixed))==1
        pair=filter(x->x.id in getindex.(fixed, "id"), rows)
        if all(x.model_pass&&x.cost_complete for x in pair)
            @test abs(pair[1].cost_USD-pair[2].cost_USD)/max(1, abs(pair[1].cost_USD))<=1e-4
        end
        # 只证明域包含，不用限时得到的较差费用反推自由度有害。
        f=only(filter(x->x["solver"]=="Gurobi", fixed))
        j=only(filter(x->x["control"]=="joint_continuous", cases))
        c=R7PlanningCase(R7NormalCase(f["normal"]), f["planning"])
        for kind in ("pipe", "source", "load")
            x=PaperRebuild.r7_unpack(f["spec"]["normal_flow"], kind*"_min")
            lo=PaperRebuild.r7_unpack(j["spec"]["normal_flow"], kind*"_min")
            hi=PaperRebuild.r7_unpack(j["spec"]["normal_flow"], kind*"_max")
            @test all(lo .<= x .<= hi)
        end
        for p in PaperRebuild.r7_planning_pairs(c), kind in ("pipe", "source", "load")
            x=PaperRebuild.r7_joint_bounds(f["spec"], p)[kind*"_min"]
            b=PaperRebuild.r7_joint_bounds(j["spec"], p)
            @test all(b[kind*"_min"] .<= x .<= b[kind*"_max"])
        end
    end
    for group in rule["groups"], control in rule["controls"]
        pair=filter(
            x->x["safety_group"]==group&&x["control"]==control&&x["solver"]=="Gurobi",
            items,
        )
        # 声明的UA改变以外，全部设备、边界和空间初态逐字段相同。
        normalized=map(pair) do x
            d=deepcopy(x["normal"])
            delete!(d, "name")
            for p in d["heat"]["pipes"], side in ("S", "R")
                @test p["UA_$(side)_W_K"]==x["UA_W_K"]
                delete!(p, "UA_$(side)_W_K")
            end
            d
        end
        @test normalized[1]==normalized[2]
        @test pair[1]["planning"]==pair[2]["planning"]
    end
    for x in rows
        rr=joint_frozen_read(joinpath(report, "records", x.id))
        r, q=rr.result, rr.validation
        @test rr.case.normal.data["battery_rule"]==rule["battery_rule"]=="per_period_exclusive_v1"
        @test r["bound_scope"]==q["bound_scope"]=="adopted_gauss_model_not_exact_PDE"
        @test q["exact_transport_optimality_verified"]===false
        @test r["full_thesis_domain_verified"]===false
        @test r["validation_reserve_sec"]==60
        @test r["wall_budget_pass"]==(r["budget_overrun_sec"]==0)
        @test abs(r["budget_overrun_sec"]-max(0, r["elapsed_sec"]-r["budget_sec"]))<0.1
        @test !(x.cost_complete&&!x.model_pass)
        if x.model_pass
            @test x.nonsimultaneous_pass
            @test q["normal_check"]["normal_validation"]["pipe_reference_pass"]
            @test all(
                w["threshold_pass"]&&w["thermal"]["thermal_model_pass"] for w in q["witness_checks"]
            )
        end
    end
end

if length(ARGS)==2
    old=abspath(ARGS[2])
    joint_check(old)
    olditems, _=joint_inputs(old)
    oldrows=collect(CSV.File(joinpath(old, "summary.csv")))
    @testset "R7-H5 explicit battery change against unchanged lossless history" begin
        for item in filter(x->x["UA_W_K"]==0, items)
            id=replace(item["id"], r"^ua0_"=>"")
            oi=only(filter(x->x["id"]==id, olditems))
            n, o=deepcopy(item["normal"]), deepcopy(oi["normal"])
            @test n["battery_rule"]=="per_period_exclusive_v1"
            @test o["battery_rule"]=="paper_sum_bound"
            for k in ("name", "battery_rule")
                delete!(n, k)
                delete!(o, k)
            end
            @test n==o
            @test item["planning"]==oi["planning"]
            for key in ("pipe_min", "pipe_max", "source_min", "source_max", "load_min", "load_max")
                @test item["spec"]["normal_flow"][key]==oi["spec"]["normal_flow"][key]
            end
            c=R7PlanningCase(R7NormalCase(item["normal"]), item["planning"])
            for pair in PaperRebuild.r7_planning_pairs(c)
                @test PaperRebuild.r7_joint_bounds(item["spec"], pair)==PaperRebuild.r7_joint_bounds(
                    oi["spec"],
                    pair,
                )
            end
            a=only(filter(x->x.id==item["id"], rows))
            b=only(filter(x->x.id==id, oldrows))
            @test a.model_pass==b.model_pass
            if a.model_pass&&a.cost_complete&&b.cost_complete
                @test abs(a.cost_USD-b.cost_USD)/max(1, abs(b.cost_USD))<=1e-4
                @test a.nonsimultaneous_pass
            end
        end
        # 旧失败标志原样保留；不是把它们重写成新域通过。
        @test count(x->x.model_pass&&!x.nonsimultaneous_pass, oldrows)==2
    end
end
