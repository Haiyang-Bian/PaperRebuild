# 检查封存图源、诊断和文档资产；同步仅创建新目录，不修改旧结果。
using TOML, SHA, CSV, Test
include("r9_preplan_diagnostic_evidence.jl")
const D=R9PreplanDiagnosticEvidence
const E=D.Evidence
root=dirname(@__DIR__)
length(ARGS) in (4, 5) || error("usage: EVIDENCE DIAGNOSTICS FIGURES ASSETS [--sync-assets]")
length(ARGS)==4 || ARGS[5]=="--sync-assets" || error("未知选项")
evidence, diagnostics, figures, assets=abspath.(ARGS[1:4])
hashfile(p) = bytes2hex(sha256(read(p)))
@testset "R9 shared preplan evidence, diagnostics and figures" begin
    @test E.check(evidence)
    @test D.check(diagnostics)
    f=TOML.parsefile(joinpath(figures, "figure.toml"))
    a=TOML.parsefile(joinpath(figures, "artifacts.toml"))["files"]
    actual=E.files(figures)
    delete!(actual, "artifacts.toml")
    @test a==actual
    @test f["schema"]=="r9-preplan-figure-v1" && !f["optimization_performed"]
    @test !f["missing_values_plotted_as_zero"] && f["residual_scope_preserved"]
    @test f["source_index_sha256"]==hashfile(joinpath(evidence, "index.toml"))
    rows=collect(CSV.File(joinpath(evidence, "primary.csv")))
    @test f["run_ids"]==[r.run_id for r in rows]
    for name in filter(x->endswith(x, ".csv"), readdir(figures))
        @test read(joinpath(figures, name))==read(joinpath(evidence, name))
    end
    if length(ARGS)==5
        target=relpath(assets, joinpath(root, "docs/src/assets"))
        !isabspath(target) && !startswith(target, "..") || error("资产必须在docs/src/assets内")
        ispath(assets) && error("不覆盖已有资产")
        mkpath(assets)
        for name in readdir(figures)
            cp(joinpath(figures, name), joinpath(assets, name))
        end
    end
    @test Set(readdir(assets))==Set(readdir(figures))
    for name in readdir(figures)
        @test hashfile(joinpath(figures, name))==hashfile(joinpath(assets, name))
    end
    for folder in (evidence, diagnostics, figures, assets),
        (dir, _, fs) in walkdir(folder),
        name in fs

        file=joinpath(dir, name)
        @test filesize(file)<=5*1024^2
        endswith(name, ".png") && continue
        bytes=read(file)
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
