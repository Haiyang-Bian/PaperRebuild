include("r5_benders_status_rules.jl")
using Test
config=normpath(joinpath(@__DIR__, "..", "configs", "r5", "benders", "status-study.toml"))
@testset "状态消歧单因素与原失败点身份" begin
    x=r5_benders_status_inputs(config)
    @test length(x.rules["probes"])==5
    @test length(x.rules["runs"])==3
    for p in x.rules["probes"]
        s=x.sources[p["source_id"]]
        @test s["status"]=="INFEASIBLE_OR_UNBOUNDED"
        @test !s["has_candidate"]&&!s["elastic"]
        b=PaperRebuild.r5_benders_bounds(x.cases[p["case"]], p["scenario"])
        @test isfinite(b.lower_cost)&&isfinite(b.upper_cost)
        @test all(isfinite(l)&&isfinite(u) for (l, u) in values(b.box))
    end
    mktempdir() do dir
        for mutate in (
            d->pop!(d["probes"]),
            d->pop!(d["runs"]),
            d->(d["subproblem_DualReductions"]=1),
            d->(d["master_DualReductions"]=0),
            d->(d["probe_values"]=[0, 1]),
            d->(d["method_budget_sec"]=1200.0),
            d->(d["probes"][1]["source_sha256"]="changed"),
            d->(d["runs"][1]["parent_sha256"]="changed"),
        )
            d=deepcopy(x.rules)
            mutate(d)
            path=joinpath(dir, "bad.toml")
            write(path, PaperRebuild.r5_market_text(d))
            @test_throws ErrorException r5_benders_status_inputs(path)
        end
    end
end
