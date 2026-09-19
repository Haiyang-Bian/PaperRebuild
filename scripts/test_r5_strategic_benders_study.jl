include("r5_strategic_benders_study_rules.jl")
using Test
config = normpath(joinpath(@__DIR__, "..", "configs", "r5", "strategic-benders", "study.toml"))
@testset "R5策略分解冻结与参考隔离" begin
    x = r5_sb_study_inputs(config)
    @test length(x.cases) == 8
    @test length(x.rules["runs"]) == 24
    for e in x.rules["runs"]
        s = r5_sb_study_spec(x.rules, e)
        @test s.feasibility == Symbol(e["route"])
        @test s.cut_arithmetic == :rational_box && s.diagnostic_scale == 1024.0
    end
    mktempdir() do dir
        for change in (
            d->pop!(d["runs"]),
            d->(d["runs"][2]=deepcopy(d["runs"][1])),
            d->(d["spec"]["relative_gap"]=1e-4),
            d->(d["budget_sec"]=1200),
            d->(d["reference_injected"]=true),
            d->(d["price_caps_imposed"]=true),
            d->(d["market_domain"]="fixed_complementarity"),
            d->(d["runs"][1]["complementarity_pattern"]=Dict()),
            d->(d["files"]["competitive_hard_zero.toml"]="changed"),
            d->(d["references"]["competitive_hard_zero.toml"]["case_sha256"]="changed"),
        )
            d = deepcopy(x.rules)
            change(d)
            p = joinpath(dir, "altered.toml")
            write(p, PaperRebuild.r5_market_text(d))
            @test_throws ErrorException r5_sb_study_inputs(p)
        end
    end
end
