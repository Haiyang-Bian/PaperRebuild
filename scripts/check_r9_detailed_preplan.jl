using PaperRebuild, TOML, Test
root = dirname(@__DIR__)
mapping = TOML.parsefile(joinpath(root, "docs/reading/ch07/resilience-detailed-preplan.toml"))
page = read(joinpath(root, mapping["page"]), String)
@testset "R9 detailed preplan mappings and stated scope" begin
    @test mapping["normal_model_unchanged"] && mapping["recovery_model_changed_explicitly"]
    @test !mapping["original_input_complete"]
    @test isfile(joinpath(root, mapping["parent"]))
    @test isfile(joinpath(root, mapping["state_model"]))
    for f in mapping["formula"]
        @test occursin("\\tag{" * f["id"] * "}", page)
        @test occursin(f["id"], read(joinpath(root, f["test"]), String))
        for api in f["api"]
            @test isdefined(PaperRebuild, Symbol(api)) && occursin(api, page)
        end
    end
    for path in mapping["test_commands"]
        @test isfile(joinpath(root, path)) && occursin(path, page)
    end
    @test length(unique(s["id"] for s in mapping["symbol"])) == length(mapping["symbol"])
    for s in mapping["symbol"]
        @test !isempty(s["unit"]) && !isempty(s["julia"]) && !isempty(s["origin"])
    end
end
