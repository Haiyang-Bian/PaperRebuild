# 故障证据交付门槛：移位原值回代、缺失状态、篡改拒绝及可公开字节边界。
using TOML, CSV, Test
include("r9_preplan_fault_evidence.jl")
const F=R9PreplanFaultEvidence
length(ARGS) in (1, 2) || error("usage: check_r9_preplan_faults.jl EVIDENCE [--replay]")
length(ARGS)==1 || ARGS[2]=="--replay" || error("未知选项")
folder=abspath(ARGS[1])
@testset "R9 independent fault evidence and preserved negative states" begin
    @test F.check(folder; replay = length(ARGS)==2)
    rows=collect(CSV.File(joinpath(folder, "comparison.csv")))
    @test length(rows)==6
    @test length(unique(r.stage for r in rows))==6
    @test all(r.critical_limit_MWh==2 for r in rows)
    @test count(r->r.model_pass, rows)==3
    for r in rows
        if !r.model_pass
            @test r.status=="infeasible_certified"
            @test isnan(r.loss_MWh) && isnan(r.loss_reduction_MWh)
            @test !r.critical_limit_pass && !r.conditional_optimality_pass
        end
    end
    # 修改仅发生在独立副本；拒绝依据冻结字节，原包始终不写入。
    scratch=mktempdir(joinpath(F.ROOT, "tmp"); prefix = "r9-fault-tamper-", cleanup = false)
    copydir=joinpath(scratch, "copy")
    cp(folder, copydir)
    open(io->write(io, "tampered\n"), joinpath(copydir, "comparison.csv"), "a")
    @test_throws ErrorException F.check(copydir)
    for (dir, _, files) in walkdir(folder), name in files
        path=joinpath(dir, name)
        @test filesize(path)<=5*1024^2
        bytes=read(path)
        for needle in (
            "C:\\Users\\",
            "C:/Users/",
            "D:\\Work\\",
            "D:/Work/",
            "WLSSECRET=",
            "LicenseID to value",
        )
            @test !occursin(needle, String(copy(bytes)))
        end
    end
end
