# 核验公开证据、图源及Documenter副本；可选同步只创建新的明确资产目录。
using TOML, SHA, CSV, Test
include("r9_resilience_evidence.jl")
const E=R9ResilienceEvidence
root=dirname(@__DIR__)
length(ARGS) in (3, 4) || error("usage: EVIDENCE FIGURES ASSETS [--sync-assets]")
length(ARGS)==3 || ARGS[4]=="--sync-assets" || error("未知选项")
evidence, figures, assets=abspath.(ARGS[1:3])
hashfile(p) = bytes2hex(sha256(read(p)))
@testset "R9 resilience evidence, figures and public boundaries" begin
    @test E.check(evidence)
    m=TOML.parsefile(joinpath(figures, "figure-source.toml"))
    @test m["schema"]=="r9-resilience-figure-v1"
    @test !m["optimization_performed"]
    @test m["evidence_manifest_sha256"]==hashfile(joinpath(evidence, "artifacts.toml"))
    @test Set(readdir(figures))==union(Set(keys(m["files"])), Set(["figure-source.toml"]))
    for (p, h) in m["files"]
        @test hashfile(E.safe(figures, p))==h
    end
    rows=collect(CSV.File(joinpath(evidence, "summary.csv")))
    @test m["run_ids"]==[r.run_id for r in rows]
    for name in ("summary.csv", "capacity.csv", "trajectories.csv", "residuals.csv", "devices.csv")
        @test read(joinpath(evidence, name))==read(joinpath(figures, name))
    end
    if length(ARGS)==4
        target=relpath(assets, joinpath(root, "docs/src/assets"))
        !isabspath(target) && !startswith(target, "..") ||
            error("资产必须在本项目docs/src/assets内")
        ispath(assets) && error("不覆盖已有资产，改用只读检查")
        mkpath(assets)
        for name in readdir(figures)
            cp(joinpath(figures, name), joinpath(assets, name))
        end
    end
    @test Set(readdir(assets))==Set(readdir(figures))
    for name in readdir(figures)
        @test hashfile(joinpath(figures, name))==hashfile(joinpath(assets, name))
    end
    for folder in (evidence, figures, assets), (dir, _, files) in walkdir(folder), name in files
        file=joinpath(dir, name)
        @test filesize(file)<=5*1024^2
        if !(endswith(name, ".png") || endswith(name, ".pdf"))
            bytes=read(file)
            for secret in (
                "C:\\Users\\",
                "C:/Users/",
                "D:\\Work\\",
                "D:/Work/",
                "WLSSECRET=",
                "LicenseID to value",
            )
                @test !occursin(secret, String(copy(bytes)))
            end
        end
    end
end
