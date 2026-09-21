using TOML, Test, PaperRebuild
root = dirname(@__DIR__)
x = TOML.parsefile(joinpath(root, "docs/reading/ch07/resilience-electric-cut.toml"))
page = read(joinpath(root, x["page"]), String)
tests = read(joinpath(root, x["test"]), String)
@testset "R9 electric cut formula, API and scope mapping" begin
    @test isfile(joinpath(root, x["parent"])) && isfile(joinpath(root, x["protocol"]))
    @test !x["original_input_complete"] && !x["model_changed"]
    for f in x["formula"]
        @test occursin("\\tag{"*f["id"]*"}", page)
        @test occursin(f["id"], tests)
        for api in f["api"]
            @test isdefined(PaperRebuild, Symbol(api)) && occursin(api, page)
        end
    end
    @test length(unique(s["id"] for s in x["symbol"])) == length(x["symbol"])
    @test all(s->!isempty(s["meaning"])&&!isempty(s["unit"])&&!isempty(s["julia"]), x["symbol"])
end
