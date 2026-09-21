using Test, TOML
include("r9_seeded_study.jl")
const SS=R9SeededStudy
root=dirname(@__DIR__)
common=joinpath(root, "results/summaries/r9-common-input-20260921-v2")
frozen=joinpath(root, "results/summaries/r9-compact-input-20260921-v1")
old=joinpath(root, "results/summaries/r9-seeded-input-20260921-v1")
@testset "R9 compact original cases, frozen protocol and implementation" begin
    b=SS.loadfreeze(common, frozen)
    p=TOML.parsefile(joinpath(old, "manifest.toml"))
    @test b.manifest["cases"]==p["cases"]
    @test b.protocol["representation"]=="r9_compact_v1"
    @test b.protocol["parent_witness_sha256"]==p["protocol"]["parent_witness_sha256"]
    @test !b.manifest["optimization_performed"]
    @test b.protocol["heldout_evaluation"]=="not_started"
    for (path, h) in b.manifest["source_hashes"]
        @test SS.S.hashfile(SS.S.safe(root, path))==h
    end
    @test TOML.parsefile(joinpath(root, "configs/r9/compact-study.toml"))==b.protocol
end
println("Frozen model representation checked; this does not run or certify scale optimization.")
