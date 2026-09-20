using Test
include("r9_pv_study.jl")
@testset "R9 frozen input and source replay before optimization" begin
    @test !isnothing(Base.invokelatest(R9PVStudy.optimizer_factory("Clarabel")))
    mktempdir() do dir
        out=joinpath(dir, "batch")
        manifest=R9PVStudy.freeze(out)
        @test length(manifest["entries"])==6
        f=R9PVStudy.frozen(out)
        @test f.c.sha256==manifest["input_sha256"]
        relative=relpath(out, pwd())
        @test R9PVStudy.frozen(relative).c.sha256==f.c.sha256
        @test Base.invokelatest(()->getfield(f.mod, :audit_r9_pv_input)(f.c)).pass
        result=Base.invokelatest(
            ()->getfield(f.mod, :solve_r9_pv_case)(
                f.c;
                optimizer = R9PVStudy.optimizer_factory("Clarabel"),
                budget_sec = 60.0,
            ),
        )
        @test result["validation"]["model_pass"]
        @test result["validation"]["terminal_pass"]
        @test result["wall_budget_pass"]
        @test_throws ErrorException R9PVStudy.freeze(out)
        path=joinpath(out, "case.toml")
        open(path, "a") do io
            println(io, "# deliberate tamper test")
        end
        @test_throws ErrorException R9PVStudy.frozen(out)
    end
end
