using Test, TOML
include("r9_numerics_study.jl")
@testset "R9 numerical snapshot is self-contained before optimization" begin
    parent = joinpath(@__DIR__, "../results/summaries/r9-pv-batch-20260920-v4")
    mktempdir() do directory
        batch = joinpath(directory, "batch")
        manifest = R9NumericsStudy.freeze(parent, batch)
        @test length(manifest["entries"]) == 6
        @test length(manifest["science_files"]) == 26
        wrapper = Module(gensym(:R9NumericsPortable))
        Base.include(wrapper, joinpath(batch, "numerics-study-source.jl"))
        f = Base.invokelatest(() -> getfield(getfield(wrapper, :R9NumericsStudy), :frozen)(batch))
        @test f.c.sha256 == manifest["input_sha256"]
        for mode in (:CF_CT, :CF_VT)
            r = Base.invokelatest(
                () -> getfield(f.mod, :solve_r9_reduced_case)(
                    f.c;
                    mode,
                    terminal = :reference_anchored,
                    budget_sec = 0,
                ),
            )
            @test r["status"] == "time_limit_no_solution"
            @test !r["validation"]["physical_pass"]
        end
        @test_throws ErrorException R9NumericsStudy.freeze(parent, batch)
        open(joinpath(batch, "code/src/formulations/r9_reduced.jl"), "a") do io
            println(io, "# tamper")
        end
        @test_throws ErrorException Base.invokelatest(
            () -> getfield(getfield(wrapper, :R9NumericsStudy), :frozen)(batch),
        )
    end
end
