using Test
include("r9_source_report.jl")
using .R9SourceReport

@testset "R9 frozen arithmetic, source replay and tamper rejection" begin
    mktempdir() do dir
        out=joinpath(dir, "report")
        a=R9SourceReport.write_report(out)
        @test !a["optimization_performed"]
        @test R9SourceReport.check_report(out)==a
        @test_throws ErrorException R9SourceReport.write_report(out)
        for name in ("inputs.toml", "arithmetic.csv", "code/src/core/r9_inputs.jl")
            path=joinpath(out, name)
            b=read(path)
            open(path, "a") do io
                write(io, "\n# intentional tamper fixture\n")
            end
            @test_throws ErrorException R9SourceReport.check_report(out)
            write(path, b)
        end
        @test R9SourceReport.check_report(out)==a
    end
end
