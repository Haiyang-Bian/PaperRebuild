include("r5_benders_study_rules.jl")
using Test
config=normpath(joinpath(@__DIR__, "..", "configs", "r5", "benders", "study.toml"))
@testset "R5正式分解规则与独立参照" begin
    x=r5_benders_study_inputs(config)
    @test length(x.rules["runs"])==42
    @test length(x.cases)==13
    for entry in x.rules["runs"]
        spec=r5_benders_study_spec(x.rules, entry)
        @test spec.feasibility==Symbol(entry["route"])
        @test spec.cut_arithmetic==:rational_box&&spec.diagnostic_scale==1024.0
    end
    mktempdir() do dir
        for change in (
            d->pop!(d["runs"]),
            d->(d["runs"][2]=deepcopy(d["runs"][1])),
            d->(d["spec"]["relative_gap"]=1e-4),
            d->(d["references"]["hard_zero.toml"]["case_sha256"]="changed"),
            d->(d["files"]["hard_zero.toml"]="changed"),
        )
            altered=deepcopy(x.rules)
            change(altered)
            file=joinpath(dir, "rules.toml")
            write(file, PaperRebuild.r5_market_text(altered))
            @test_throws ErrorException r5_benders_study_inputs(file)
        end
    end
end
