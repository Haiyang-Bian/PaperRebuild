# 仅重读和篡改临时副本，不重新优化，不改原结果。
using Test, TOML
include("seal_r9_common_witness.jl")
const E=R9CommonEvidence
length(ARGS)==2 || error("usage: FROZEN_INPUT SEALED_EVIDENCE")
input, evidence=abspath.(ARGS)
root=dirname(@__DIR__)
mkpath(joinpath(root, "tmp"))
scratch=mktempdir(joinpath(root, "tmp"); prefix = "r9-common-evidence-", cleanup = false)
movedinput=joinpath(scratch, "input")
moved=joinpath(scratch, "evidence")
cp(input, movedinput)
cp(evidence, moved)
function refresh_manifest(out)
    m=TOML.parsefile(joinpath(out, "delivery.toml"))
    for rel in keys(m["files"])
        m["files"][rel]=E.hashfile(E.safe(out, rel))
    end
    E.toml(joinpath(out, "delivery.toml"), m)
end
@testset "R9 common evidence portability and false success rejection" begin
    # 移位后不依赖results/runs；完整原模型重读仅执行这一次。
    @test E.check(movedinput, moved)
    witness=joinpath(moved, "run/witness.toml")
    bytes=read(witness)
    open(io->write(io, "\n"), witness, "a")
    @test_throws ErrorException E.check(movedinput, moved; replay = false)
    write(witness, bytes)
    @test E.check(movedinput, moved; replay = false)
    statuspath=joinpath(moved, "run/status.toml")
    status=TOML.parsefile(statuspath)
    for field in ("has_common_candidate", "budget_pass")
        bad=deepcopy(status)
        bad[field]=false
        E.toml(statuspath, bad)
        refresh_manifest(moved)
        @test_throws ErrorException E.check(movedinput, moved; replay = false)
    end
    bad=deepcopy(status)
    bad["elapsed_sec"]=601.0
    E.toml(statuspath, bad)
    refresh_manifest(moved)
    @test_throws ErrorException E.check(movedinput, moved; replay = false)
    bad=deepcopy(status)
    bad["new_optimization_performed"]=true
    E.toml(statuspath, bad)
    refresh_manifest(moved)
    @test_throws ErrorException E.check(movedinput, moved; replay = false)
    bad=deepcopy(status)
    delete!(bad["schemes"], "3C")
    E.toml(statuspath, bad)
    refresh_manifest(moved)
    @test_throws ErrorException E.check(movedinput, moved; replay = false)
    E.toml(statuspath, status)
    for scheme in ("3A", "3B", "3C")
        p=joinpath(moved, "run/validation-"*scheme*".toml")
        v=TOML.parsefile(p)
        bad=deepcopy(v)
        bad["original_risk_optimality_claim"]=true
        E.toml(p, bad)
        refresh_manifest(moved)
        @test_throws ErrorException E.check(movedinput, moved; replay = false)
        E.toml(p, v)
    end
    refresh_manifest(moved)
    @test E.check(movedinput, moved; replay = false)
    @test E.hashfile(joinpath(evidence, "run/witness.toml"))==E.hashfile(witness)
    @test_throws ErrorException E.safe(moved, "../escape")
    @test_throws ErrorException E.safe(moved, "/escape")
    @test_throws ErrorException E.safe(moved, "C:/escape")
    @test_throws ErrorException E.safe(moved, "run\\status.toml")
end
