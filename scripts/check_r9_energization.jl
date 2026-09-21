# 显式带电域来源/公式/API映射；科学结论由独立求解和重读测试提供。
using TOML, Test, PaperRebuild
root=dirname(@__DIR__)
d=TOML.parsefile(joinpath(root, "docs/reading/ch07/resilience-energization.toml"))
@testset "R9 partial-energization contract and formula mapping" begin
    source=TOML.parsefile(joinpath(root, "docs/reading/ch07/resilience-review.toml"))
    @test d["source_sha256"]==source["source_sha256"]
    @test d["pdf_pages"]==[113, 114]
    @test d["domain"]=="partial_energization_v1"
    @test d["chp_commitment_preserved"] && d["shedding_bounds_preserved"]
    for key in (
        "normal_network_changed",
        "old_results_rewritten",
        "black_start_or_frequency_certified",
        "heating_pump_auxiliary_electricity_added",
        "chapter_7_5_scale_optimization_performed",
    )
        @test !d[key]
    end
    page=read(joinpath(root, d["human_page"]), String)
    @test [f["id"] for f in d["formula"]]==["R9-RE$i" for i in 1:5]
    for f in d["formula"]
        @test occursin("\\tag{"*f["id"]*"}", page)
        @test occursin(f["id"], read(joinpath(root, f["test"]), String))
        for api in f["api"]
            @test isdefined(PaperRebuild, Symbol(api))
        end
    end
    for script in d["test_commands"]
        @test isfile(joinpath(root, script)) && occursin(script, page)
    end
end
