# 专项验证只读取冻结包；移动目录、字节篡改和重签摘要均不能制造证书。
using Test, TOML, SHA
include("r9_distributed_diagnostics.jl")
const D=R9DistributedDiagnostics
length(ARGS)==1 || error("usage: test_r9_distributed_diagnostics.jl EVIDENCE")
source=abspath(only(ARGS))
@testset "R9 fixed heat witness and reported-objective evidence" begin
    @test D.check(source)
    m=TOML.parsefile(joinpath(source, "evidence.toml"))
    h=TOML.parsefile(joinpath(source, "heat-witness.toml"))
    @test h["gap_MW"]>0.2575 && h["gap_MW"]<0.2576
    @test !m["solver_used_for_replay"] && h["posthoc_region"]
    mktempdir() do temp
        moved=joinpath(temp, "moved")
        cp(source, moved)
        @test D.check(moved)
        path=joinpath(moved, "heat-witness.toml")
        h["gap_MW"]=100.0
        D.S.toml(path, h)
        @test_throws ErrorException D.check(moved)
        # 更新摘要哈希仍须经过原值重推，不能只检查文件数量或摘要一致。
        m["derived_files"]["heat-witness.toml"]=bytes2hex(sha256(read(path)))
        D.S.toml(joinpath(moved, "evidence.toml"), m)
        @test_throws ErrorException D.check(moved)
    end
end
