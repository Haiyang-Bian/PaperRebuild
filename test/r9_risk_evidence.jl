module R9RiskEvidenceTests
using Test, CSV, SHA
include(joinpath(@__DIR__, "../scripts/r9_reserve_evidence.jl"))
const E=R9ReserveEvidence
@testset "R9 empty scientific tables and exact numerical carriers" begin
    for name in (:trajectories, :scenarios, :residuals)
        file, content=only(E.table_parts(name, NamedTuple[]))
        @test file==string(name)*".csv"
        @test isempty(CSV.File(IOBuffer(content)))
        @test :method in propertynames(CSV.File(IOBuffer(content)))
    end
    @test_throws ErrorException E.table_parts(:summary, NamedTuple[])
    mktempdir() do tmp
        mkpath(joinpath(tmp, "objects"))
        content=Vector{UInt8}(codeunits(repeat("原始见证α\n", 350000)))
        h=E.Objects.object(tmp, content)
        @test E.Objects.bytes(tmp, h)==content
        @test all(
            filesize(joinpath(tmp, "objects", x))<=4*1024^2 for
            x in readdir(joinpath(tmp, "objects"))
        )
        @test_throws ErrorException E.Objects.bytes(tmp, "../escape")
        firstpart=first(readdir(joinpath(tmp, "objects")))
        write(joinpath(tmp, "objects", firstpart), "changed")
        @test_throws ErrorException E.Objects.bytes(tmp, h)
    end
end
end
