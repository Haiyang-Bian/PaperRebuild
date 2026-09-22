using TOML, Test, PaperRebuild
root=dirname(@__DIR__)
d=TOML.parsefile(joinpath(root, "docs/reading/ch07/resilience-pilot.toml"))
p=TOML.parsefile(joinpath(root, d["protocol"]))
page=read(joinpath(root, d["page"]), String)
@testset "R9-RW1 R9-RW2 mapping and declared scientific boundaries" begin
    @test d["common_quarter_hour_grid"] && !d["original_input_complete"]
    @test !d["scale_fault_universe_certified"] && !d["old_results_rewritten"]
    @test [20, 23] in p["electric"]["base_switches"]
    @test p["pilot"]["event_start_h"]==10 && p["pilot"]["event_end_h"]==14
    @test p["electric"]["fault_budget"]==3
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
