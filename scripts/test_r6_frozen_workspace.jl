using Test
include("r6_frozen_workspace.jl")
length(ARGS) == 2 || error("usage: test_r6_frozen_workspace.jl <batch> <prepared-workspace>")
batch, workspace = ARGS
@testset "R6 frozen execution file identity and tamper rejection" begin
    meta = check_r6_workspace(batch, workspace)
    @test meta["scientific_sources_unchanged"]
    for bad in ("../other", "C:/other", "/other", "a\\b", "a/../b", "", "a//b")
        @test_throws ErrorException r6_workspace_path(workspace, bad)
    end
    @test_throws ErrorException prepare_r6_workspace(batch, workspace)
    @test_throws ErrorException run_r6_workspace(batch, workspace, "freeze")
    @test_throws ErrorException run_r6_workspace(batch, workspace, "report-check")
    mktempdir() do tmp
        altered = joinpath(tmp, "changed")
        cp(workspace, altered)
        p = "src/PaperRebuild.jl"
        original = read(joinpath(altered, p))
        write(joinpath(altered, p), vcat(original, codeunits("\n# changed\n")))
        @test_throws ErrorException check_r6_workspace(batch, altered)
        m = TOML.parsefile(joinpath(altered, "execution.toml"))
        m["sources"][p] = bytes2hex(sha256(read(joinpath(altered, p))))
        open(joinpath(altered, "execution.toml"), "w") do io
            TOML.print(io, m; sorted = true)
        end
        @test_throws ErrorException check_r6_workspace(batch, altered)
    end
    mktempdir() do tmp
        altered = joinpath(tmp, "extra")
        cp(workspace, altered)
        write(joinpath(altered, "unregistered.jl"), "error(\"unexpected\")\n")
        @test_throws ErrorException check_r6_workspace(batch, altered)
    end
    mktempdir() do tmp
        altered = joinpath(tmp, "reporter")
        cp(workspace, altered)
        p = first(R6_WORKSPACE_REPORTERS)
        write(joinpath(altered, p), "error(\"changed reporter\")\n")
        @test_throws ErrorException check_r6_workspace(batch, altered)
        m = TOML.parsefile(joinpath(altered, "execution.toml"))
        m["reporters"][p] = bytes2hex(sha256(read(joinpath(altered, p))))
        open(joinpath(altered, "execution.toml"), "w") do io
            TOML.print(io, m; sorted = true)
        end
        @test_throws ErrorException check_r6_workspace(batch, altered)
    end
end
