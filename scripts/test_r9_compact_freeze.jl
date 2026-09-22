using Test, TOML
include("r9_seeded_study.jl")
const SS=R9SeededStudy
root=dirname(@__DIR__)
common=joinpath(root, "results/summaries/r9-common-input-20260921-v2")
witness=joinpath(root, "results/summaries/r9-common-evidence-20260921-v1")
old=joinpath(root, "results/summaries/r9-seeded-input-20260921-v1")
protocol=joinpath(root, "configs/r9/compact-study.toml")
@testset "R9 compact freeze, original identities and old-load compatibility" begin
    prior=SS.loadfreeze(common, old)
    @test get(prior.protocol, "representation", "original")=="original"
    mktempdir() do dir
        frozen=joinpath(dir, "compact")
        SS.freeze(common, witness, frozen; protocol_file = protocol)
        bundle=SS.loadfreeze(common, frozen)
        @test bundle.protocol["representation"]=="r9_compact_v1" && bundle.protocol["solver_log"]
        @test bundle.manifest["cases"]==prior.manifest["cases"]
        @test bundle.witness==prior.witness
        @test bundle.manifest["protocol_file"]=="configs/r9/compact-study.toml"
        for key in keys(prior.protocol)
            key=="comparison_scope" && continue
            @test bundle.protocol[key]==prior.protocol[key]
        end
        lib=bundle.state.bundle.lib
        Base.invokelatest() do
            c=getfield(lib, :R5RiskCase)(
                TOML.parsefile(joinpath(root, "configs/r5/risk/hard_zero.toml")),
            )
            b=getfield(lib, :build_r9_compact_risk)(c)
            @test b.representation=="r9_compact_v1"
        end
        @test_throws ErrorException SS.freeze(common, witness, frozen; protocol_file = protocol)
        rel="implementation/src/formulations/r9_compact_risk.jl"
        path=joinpath(frozen, rel)
        bytes=read(path)
        open(io->write(io, "# altered"), path, "a")
        @test_throws ErrorException SS.loadfreeze(common, frozen)
        write(path, bytes)
        @test SS.loadfreeze(common, frozen).manifest["cases"]==prior.manifest["cases"]
        mpath=joinpath(frozen, "manifest.toml")
        manifest=TOML.parsefile(mpath)
        manifest["protocol_file"]="../outside.toml"
        SS.S.toml(mpath, manifest)
        write(joinpath(frozen, "manifest.sha256"), SS.S.hashfile(mpath)*"\n")
        @test_throws ErrorException SS.loadfreeze(common, frozen)
    end
end
