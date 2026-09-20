using Test, PaperRebuild, TOML, CSV
include("r7_flow_planning_study.jl")
length(ARGS)==1 || error("usage: check_r7_flow_planning_results.jl REPORT")
report=abspath(only(ARGS))
joint_check(report)
items, rule=joint_inputs(report)
rows=collect(CSV.File(joinpath(report, "summary.csv")))
@testset "R7-J4 frozen domains paired objectives and independent witnesses" begin
    @test length(rows)==rule["record_count"]==12
    @test Set(x.id for x in rows)==Set(x["id"] for x in items)
    for group in rule["groups"]
        cases=filter(x->x["group"]==group, items)
        @test length(unique(x["case_sha256"] for x in cases))==1
        fixed=filter(x->x["control"]=="prescribed", cases)
        @test length(unique(x["spec_sha256"] for x in fixed))==1
        pair=filter(x->x.group==group&&x.control=="prescribed", rows)
        @test length(pair)==2
        if all(x.model_pass&&x.cost_complete for x in pair)
            @test abs(pair[1].cost_USD-pair[2].cost_USD)/max(1, abs(pair[1].cost_USD))<=1e-4
        else
            @test all(x.status=="infeasible_certified" for x in pair)
        end
        # 同输入的域包含；只检验边界，不能由限时劣候选否定灵活性。
        fixitem=only(filter(x->x["control"]=="prescribed"&&x["solver"]=="Gurobi", cases))
        allitem=only(filter(x->x["control"]=="joint_continuous", cases))
        c=R7PlanningCase(R7NormalCase(fixitem["normal"]), fixitem["planning"])
        for kind in ("pipe", "source", "load")
            f=PaperRebuild.r7_unpack(fixitem["spec"]["normal_flow"], kind*"_min")
            lo=PaperRebuild.r7_unpack(allitem["spec"]["normal_flow"], kind*"_min")
            hi=PaperRebuild.r7_unpack(allitem["spec"]["normal_flow"], kind*"_max")
            @test all(lo .<= f .<= hi)
        end
        for p in PaperRebuild.r7_planning_pairs(c), kind in ("pipe", "source", "load")
            f=PaperRebuild.r7_joint_bounds(fixitem["spec"], p)[kind*"_min"]
            b=PaperRebuild.r7_joint_bounds(allitem["spec"], p)
            @test all(b[kind*"_min"] .<= f .<= b[kind*"_max"])
        end
    end
    for x in rows
        @test !(x.cost_complete&&!x.model_pass)
        rr=joint_frozen_read(joinpath(report, "records", x.id))
        @test rr.case.sha256==only(i["case_sha256"] for i in items if i["id"]==x.id)
        @test rr.result["full_thesis_domain_verified"]===false
        if x.model_pass
            @test all(w["threshold_pass"] for w in rr.validation["witness_checks"])
            @test !haskey(rr.result["normal"], "lower_bound_USD")
        end
    end
end

@testset "R7-J5 healthy-line reserve mechanism from frozen values" begin
    fixed=joint_frozen_read(joinpath(report, "records", "healthy_zero_loss_prescribed_gurobi"))
    free=joint_frozen_read(
        joinpath(report, "records", "healthy_zero_loss_recovery_continuous_gurobi"),
    )
    d=fixed.case.normal.data
    w=2
    r=first(fixed.result["witnesses"])
    m=PaperRebuild.r7_unpack(r["values"], "m_source")[1, 1]
    return_K=PaperRebuild.r7_unpack(r["thermal_values"], "R")[1, 1, w]
    Hmax=d["heat"]["c_J_kgK"]/1e6*m*(d["heat"]["S_max_K"]-return_K)
    @test Hmax≈0.631 atol=1e-7
    g=only(i for (i, x) in enumerate(d["devices"]) if x["kind"]=="BES")
    dev=d["devices"][g]
    @test dev["eta_ch"]==dev["eta_dis"]==1
    reserve=d["dt_h"]*(d["electric"]["load_MW"][2][2]-Hmax)-dev["initial_MWh"][w]
    @test reserve≈0.019 atol=1e-7
    old_ch=PaperRebuild.r7_unpack(fixed.result["normal"]["values"], "P_ch")
    @test d["dt_h"]*sum(old_ch[g, :, w])≈reserve atol=1e-7
    for key in ("P_ch", "P_dis")
        x=PaperRebuild.r7_unpack(free.result["normal"]["values"], key)
        @test maximum(abs.(x[g, :, w]))<1e-7
    end
    change=fixed.validation["cost_USD"]-free.validation["cost_USD"]
    @test change≈2*d["probabilities"][w]*dev["cost_P_USD_MWh"]*reserve atol=1e-7
end
