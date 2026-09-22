# 第7.5节币种接口映射检查；数学与存档行为由两个专项测试入口验证。
using TOML, Test, PaperRebuild
root=dirname(@__DIR__)
c=TOML.parsefile(joinpath(root, "docs/reading/ch07/resilience-currency.toml"))
@testset "R9 resilience currency scope and formula mapping" begin
    @test c["schema"]=="r9-resilience-currency-contract-v1"
    @test c["supported_currency"]==["USD", "CNY"]
    @test !c["exchange_rate_applied"] && !c["old_results_rewritten"]
    @test !c["chapter_7_5_optimization_performed"]
    @test !c["critical_load_objective_implemented_in_this_contract"] &&
          !c["event_grid_conversion_implemented"]
    @test isfile(joinpath(root, c["critical_load_followup"]))
    page=read(joinpath(root, c["human_page"]), String)
    @test Set(f["id"] for f in c["formula"])==Set(["R9-RC1", "R9-RC2", "R9-RC3"])
    for f in c["formula"]
        @test occursin("\\tag{"*f["id"]*"}", page)
        @test occursin(f["id"], read(joinpath(root, f["test"]), String))
        for api in f["api"]
            @test isdefined(PaperRebuild, Symbol(api))
        end
        for path in f["implementation"]
            @test isfile(joinpath(root, path))
        end
    end
    for command in c["test_commands"]
        @test isfile(joinpath(root, command)) && occursin(command, page)
    end
    @test isfile(joinpath(root, c["source_review"]))
end
