# 图源、文档副本、正式冻结源码及篡改拒绝；不调用优化器。
using TOML, SHA, CSV, Test
include("r9_fixed_evidence.jl")
root=dirname(@__DIR__)
archive=joinpath(root, "results/summaries/r9-fixed-20260921-v4")
figures=joinpath(root, "results/summaries/r9-fixed-figures-20260921-v4")
assets=joinpath(root, "docs/src/assets/r9-fixed")
ARGS in (String[], ["--sync-docs"]) || error("usage: check_r9_fixed_delivery.jl [--sync-docs]")
hashfile(p) = bytes2hex(sha256(read(p)))
f=TOML.parsefile(joinpath(figures, "figure.toml"))
if "--sync-docs" in ARGS
    mkpath(assets)
    for p in [sort(collect(keys(f["files"]))); "figure.toml"]
        cp(joinpath(figures, p), joinpath(assets, p); force = true)
    end
end
@testset "R9 fixed source, figures, documentation and tamper rejection" begin
    index=TOML.parsefile(joinpath(archive, "index.toml"))
    formal=index["formal"]
    manifest=R9FixedEvidence.parseobject(archive, formal["manifest.toml"])
    for path in manifest["science_files"]
        @test hashfile(joinpath(root, path))==formal["code/"*path]
    end
    for (p, h) in TOML.parsefile(joinpath(archive, "artifact-hashes.toml"))["files"]
        @test hashfile(joinpath(archive, p))==h
    end
    for (p, h) in f["files"]
        @test hashfile(joinpath(figures, p))==h
        @test hashfile(joinpath(assets, p))==h
    end
    @test read(joinpath(assets, "figure.toml"))==read(joinpath(figures, "figure.toml"))
    @test f["source_index_sha256"]==hashfile(joinpath(archive, "index.toml"))
    @test f["origin"]=="synthetic" && !f["solver_run"]
    for p in ("summary.csv", "ratios.csv", "trajectories.csv", "diagnostics.csv")
        @test read(joinpath(archive, p))==read(joinpath(figures, p))
    end
    summary=collect(CSV.File(joinpath(archive, "summary.csv")))
    @test length(summary)==4
    @test count(x->x.model_pass, summary)==2
    @test count(x->x.physical_pass, summary)==2
    @test all(!x.kkt_trusted for x in summary)
    @test all(x.budget_pass for x in summary)
    ratios=collect(CSV.File(joinpath(archive, "ratios.csv")))
    @test all(x.rows==111 for x in ratios if x.scope=="periodic")
    @test all(x.rows==9096 for x in ratios if x.scope=="physical")
    original_hashes=Set(values(formal))
    for payload in values(index["diagnostics"])
        union!(original_hashes, values(payload))
    end
    union!(original_hashes, values(index["development_logs"]))
    push!(original_hashes, index["audit_source"])
    for hash in original_hashes
        content=String(R9FixedEvidence.bytes(archive, hash))
        @test !occursin(root, content)
        @test !occursin(r"[A-Za-z]:[\\/]Users[\\/]", content)
        @test !occursin(r"LicenseID to value [0-9]", content)
    end
    for (directory, _, names) in walkdir(archive), name in names
        @test filesize(joinpath(directory, name))<=5*1024^2
    end
    # 只操作新建的工作区临时目录，不修改任何原对象。
    mktempdir(joinpath(root, "tmp"); prefix = "r9-fixed-tamper-") do scratch
        @test startswith(
            abspath(scratch),
            abspath(joinpath(root, "tmp"))*Base.Filesystem.path_separator,
        )
        mkpath(joinpath(scratch, "objects"))
        hash=formal["case.toml"]
        write(joinpath(scratch, "objects", hash), R9FixedEvidence.bytes(archive, hash))
        @test R9FixedEvidence.bytes(scratch, hash)==R9FixedEvidence.bytes(archive, hash)
        write(joinpath(scratch, "objects", hash), "altered")
        @test_throws ErrorException R9FixedEvidence.bytes(scratch, hash)
        @test_throws ErrorException R9FixedEvidence.bytes(scratch, "../case")
    end
end
