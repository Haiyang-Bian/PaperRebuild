module HistoricalEvidenceTests
using Test
include(joinpath(@__DIR__, "..", "scripts", "check_historical_evidence.jl"))
using .HistoricalEvidenceReplay

@testset "Historical evidence identity and immutable version selection" begin
    @test length(HistoricalEvidenceReplay.BATCHES) == 4
    @test all(
        occursin(r"^[0-9a-f]{40}$", x.commit) for x in values(HistoricalEvidenceReplay.BATCHES)
    )
    @test_throws ErrorException HistoricalEvidenceReplay.prepare("../arbitrary")
    @test_throws ErrorException HistoricalEvidenceReplay.replay("r5-risk"; mode = "study")
    @test_throws ErrorException HistoricalEvidenceReplay.replay("r5-risk"; mode = "rewrite")
    mktempdir() do dir
        original, current = joinpath(dir, "original"), joinpath(dir, "current")
        mkpath(original)
        mkpath(current)
        for path in (original, current)
            write(joinpath(path, "report.toml"), "origin = \"synthetic\"\n")
            write(joinpath(path, "artifact-hashes.toml"), "[sha256]\n")
        end
        @test HistoricalEvidenceReplay.verify_identity(original, current)["origin"] == "synthetic"
        write(joinpath(current, "report.toml"), "origin = \"rewritten\"\n")
        @test_throws ErrorException HistoricalEvidenceReplay.verify_identity(original, current)
        cp(joinpath(original, "report.toml"), joinpath(current, "report.toml"); force = true)
        write(joinpath(current, "artifact-hashes.toml"), "[sha256]\nchanged = \"resigned\"\n")
        @test_throws ErrorException HistoricalEvidenceReplay.verify_identity(original, current)
    end
end
end
