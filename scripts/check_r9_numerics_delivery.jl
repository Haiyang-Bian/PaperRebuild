# 归档自包含、原字节、路径及图文副本检查；不优化，不改写存档。
using Test, TOML, SHA
root=normpath(joinpath(@__DIR__, ".."))
hashfile(p) = bytes2hex(sha256(read(p)))
names=[
    "r9-numerics-20260921-v2",
    "r9-numerics-report-20260921-v1",
    "r9-numerics-audit-20260921-v1",
    "r9-numerics-cost-20260921-v1",
    "r9-numerics-figures-20260921-v1",
]
folders=[joinpath(root, "results/summaries", p) for p in names]
@testset "R9 portable numerical evidence and source identity" begin
    for (folder, meta) in zip(
        folders,
        ["manifest.toml", "report.toml", "manifest.toml", "manifest.toml", "figure-config.toml"],
    )
        saved=TOML.parsefile(joinpath(folder, meta))
        for (p, h) in saved["files"]
            @test !isabspath(p) && !occursin("..", p)
            @test hashfile(joinpath(folder, p))==h
        end
        for (dir, _, files) in walkdir(folder), file in files
            p=joinpath(dir, file)
            @test filesize(p)<5*1024*1024
            splitext(p)[2] in (".jl", ".md", ".csv", ".toml", ".json", ".svg") || continue
            text=read(p, String)
            @test !occursin(r"[A-Za-z]:[\\/](?:Users|Work|projects)[\\/]", text)
            @test !occursin(r"(?:ghp_|github_pat_|sk-proj-)[A-Za-z0-9_]{16,}", text)
        end
    end
    b=TOML.parsefile(joinpath(folders[1], "manifest.toml"))
    @test b["parent_manifest_sha256"]==hashfile(
        joinpath(root, "results/summaries/r9-pv-batch-20260920-v4/manifest.toml"),
    )
    @test b["input_sha256"]=="d514c3c2e94f962feb65717da43920559b4bcbca8613d2abcef2e1ed292d51b0"
    if ARGS==["--current"]
        for p in b["science_files"]
            @test read(joinpath(root, p))==read(joinpath(folders[1], "code", p))
        end
    elseif !isempty(ARGS)
        error("usage: check_r9_numerics_delivery.jl [--current]")
    end
    @test read(joinpath(folders[5], "F35-r9-numerics.png"))==read(
        joinpath(root, "docs/src/assets/r9-numerics-20260921-v1/F35-r9-numerics.png"),
    )
    for mode in ("ct", "vt")
        cert=joinpath(folders[3], "original-"*mode, "certificate.toml")
        checked=TOML.parsefile(joinpath(folders[3], "original-"*mode*"-check/check.toml"))
        @test checked["certificate_sha256"]==hashfile(cert)
        @test checked["original_row_identity_pass"]
    end
    cost=TOML.parsefile(joinpath(folders[4], "manifest.toml"))
    for (id, h) in cost["run_hashes"]
        @test hashfile(joinpath(folders[1], "runs", id, "result.toml"))==h
    end
end
