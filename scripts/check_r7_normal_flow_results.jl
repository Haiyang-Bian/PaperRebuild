using Test, CSV, TOML
include("r7_normal_flow_study.jl")
length(ARGS)==1 || error("usage: check_r7_normal_flow_results.jl REPORT")
dir=abspath(ARGS[1]);
flow_check(dir)
items, _=flow_inputs(dir)
summary=collect(CSV.File(joinpath(dir, "summary.csv")))
trajectory=collect(CSV.File(joinpath(dir, "trajectories.csv")))
@testset "R7 normal flow frozen pair evidence" begin
    @test Set(String(r.record) for r in summary)==Set(x["id"] for x in items)
    @test length(summary)==length(items)
    for item in items
        a=flow_read(joinpath(dir, "records", item["id"]))
        r=a.result
        q=a.validation
        row=only(filter(x->x.record==item["id"], summary))
        @test row.run_id==r["run_id"]&&row.status==r["status"]
        @test row.model_pass==r["candidate_accepted"]&&row.cost_complete==r["domain_cost_complete"]
        rows=filter(x->x.record==item["id"], trajectory)
        if r["candidate_accepted"]
            @test Float64(row.cost_USD)==q["cost_USD"]
            f=PaperRebuild.r7_unpack(r["flow_values"], "pipe")
            @test length(rows)==length(f)*length(a.case.data["probabilities"])
            @test length(Set((x.pipe, x.time_h, x.scenario) for x in rows))==length(rows)
            for x in rows
                @test x.run_id==r["run_id"]&&x.flow_kg_s==f[x.pipe, x.time_h]
                for (col, key, offset) in (
                    (:outlet_S_K, "τ_pipe_S", 0),
                    (:outlet_R_K, "τ_pipe_R", 0),
                    (:inventory_S_MWh, "E_pipe_S", 1),
                    (:inventory_R_MWh, "E_pipe_R", 1),
                )
                    @test getproperty(x, col)==PaperRebuild.r7_unpack(r["values"], key)[
                        x.pipe,
                        x.time_h+offset,
                        x.scenario,
                    ]
                end
            end
        else
            @test ismissing(row.cost_USD)&&isempty(rows)
        end
    end
    for group in unique(x["group"] for x in items)
        chosen=filter(x->x["group"]==group, items)
        a=only(filter(x->x["control"]=="prescribed"&&x["solver"]=="HiGHS", chosen))
        b=only(filter(x->x["control"]=="prescribed"&&x["solver"]=="Gurobi", chosen))
        f=only(filter(x->x["control"]=="continuous", chosen))
        @test a["case_sha256"]==b["case_sha256"]==f["case_sha256"]
        @test a["spec_sha256"]==b["spec_sha256"]
        x, y, z=(flow_read(joinpath(dir, "records", i["id"])) for i in (a, b, f))
        if x.result["candidate_accepted"]&&y.result["candidate_accepted"]
            @test abs(x.validation["cost_USD"]-y.validation["cost_USD"])/max(
                1,
                abs(x.validation["cost_USD"]),
            )<=1e-4
        end
        # 同一物理输入，固定域嵌入自由域；若自由域限时，只核对有效下界而不强求候选更优。
        for k in ("pipe", "source", "load")
            fixed=PaperRebuild.r7_unpack(a["spec"], k*"_min")
            lo=PaperRebuild.r7_unpack(f["spec"], k*"_min")
            hi=PaperRebuild.r7_unpack(f["spec"], k*"_max")
            @test all(lo .<= fixed .<= hi)
        end
        if x.result["candidate_accepted"]&&haskey(z.result, "lower_bound_USD")
            @test z.result["lower_bound_USD"]<=x.validation["cost_USD"]+1e-4*max(
                1,
                abs(x.validation["cost_USD"]),
            )
        end
        if z.result["domain_cost_complete"]&&x.result["candidate_accepted"]
            @test z.validation["cost_USD"]<=x.validation["cost_USD"]+1e-4*max(
                1,
                abs(x.validation["cost_USD"]),
            )
        end
        @test !z.result["full_preplan_optimality_verified"]
    end
end
