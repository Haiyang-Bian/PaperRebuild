using Test
include("r7_normal.jl")

@testset "R7 normal CLI and event evidence tamper" begin
    root=normpath(joinpath(@__DIR__, ".."))
    mktempdir(root) do folder
        parent=joinpath(folder, "normal")
        event=joinpath(folder, "event")
        normal_cli(["run", joinpath(root, "configs/r7/normal-hand.toml"), parent])
        normal_cli(["check", parent])
        normal_cli(["event", parent, "2", "1", "0.5", "2.0", event])
        normal_cli(["check-event", parent, event])
        @test isfile(joinpath(event, "handoff.toml"))
        @test length(TOML.parsefile(joinpath(event, "event.toml"))["records"])==2
        @test_throws ErrorException normal_cli(["event", parent, "2", "1", "0.5", "2.0", event])
        file=joinpath(event, "handoff.toml")
        d=TOML.parsefile(file)
        d["initial_pipe_profiles"][1]["mean_K"]+=0.1
        write(file, PaperRebuild.r7_text(d))
        manifest=joinpath(event, "event-files.toml")
        hashes=TOML.parsefile(manifest)
        hashes["files"]["handoff.toml"]=bytes2hex(sha256(read(file)))
        write(manifest, PaperRebuild.r7_text(hashes))
        @test_throws ErrorException normal_cli(["check-event", parent, event])
        @test_throws ErrorException normal_cli([
            "event",
            parent,
            "4",
            "2",
            "0.5",
            "2.0",
            joinpath(folder, "invalid"),
        ])
        @test !ispath(joinpath(folder, "invalid"))
    end
end
