using PaperRebuild, Test, TOML
root=dirname(@__DIR__)
d=TOML.parsefile(joinpath(root, "docs/reading/ch07/resilience-preplan.toml"))
page=read(joinpath(root, d["page"]), String)
@testset "R9 prescribed preplan mappings and declared boundaries" begin
    @test d["normal_model_unchanged"] && d["fault_subset_explicit"]
    @test !d["original_input_complete"]
    @test occursin(d["source_ambiguity"], read(joinpath(root, d["source_ledger"]), String))
    for f in d["formula"]
        @test occursin("\\tag{"*f["id"]*"}", page)
        @test occursin(f["id"], read(joinpath(root, f["test"]), String))
        for api in f["api"]
            @test isdefined(PaperRebuild, Symbol(api))
        end
    end
    for p in d["test_commands"]
        @test isfile(joinpath(root, p)) && occursin(p, page)
    end
    for f in d["diagnostic"]
        @test occursin("\\tag{"*f["id"]*"}", page)
        @test isfile(joinpath(root, f["script"])) && isfile(joinpath(root, f["validator"]))
        @test isfile(joinpath(root, f["evidence"], "diagnostics.csv"))
        @test !f["full_physical_or_all_fault_worst_loss_claim"]
    end
end
