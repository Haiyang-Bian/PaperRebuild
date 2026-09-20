using Test, CSV, TOML, SHA
length(ARGS)==4||error("usage: check_r8_figures.jl REPORT AUDIT FIGURES DOCUMENT_IMAGE")
report, audit, figures, docimage=abspath.(ARGS)
hashfile(p) = bytes2hex(sha256(read(p)))
f=TOML.parsefile(joinpath(figures, "figure.toml"))
a=TOML.parsefile(joinpath(audit, "audit.toml"))
@testset "R8 F31 sources, residuals and document copy" begin
    @test f["origin"]=="synthetic"
    @test f["report_manifest_sha256"]==hashfile(joinpath(report, "report-hashes.toml"))
    @test f["audit_sha256"]==hashfile(joinpath(audit, "audit.toml"))
    @test Set(readdir(figures))==union(Set(keys(f["files"])), Set(["figure.toml"]))
    for (p, h) in f["files"]
        @test hashfile(joinpath(figures, p))==h
    end
    for p in ("summary.csv", "events.csv")
        @test read(joinpath(report, p))==read(joinpath(figures, p))
    end
    rows=collect(CSV.File(joinpath(report, "summary.csv")))
    @test f["run_ids"]==[r.run_id for r in rows]
    residuals=vcat([collect(CSV.File(joinpath(audit, p))) for p in a["residual_parts"]]...)
    points=collect(CSV.File(joinpath(figures, "residual-points.csv")))
    @test length(points)==length(unique(z.id for z in residuals))
    for p in points
        rr=filter(z->z.id==p.id, residuals)
        ratio=maximum(
            z.tolerance>0 ? z.residual/z.tolerance : z.residual==0 ? 0.0 : Inf for z in rr
        )
        @test p.residual_ratio==ratio
        @test rows[p.index].id==p.id && rows[p.index].run_id==p.run_id
    end
    @test read(joinpath(figures, "F31-r8-tradeoff.png"))==read(docimage)
    png=read(joinpath(figures, "F31-r8-tradeoff.png"))
    be32(bytes) = foldl((x, y)->(x<<8)|UInt32(y), bytes; init = UInt32(0))
    @test Int[be32(png[17:20]), be32(png[21:24])]==f["size_pixels"]
    @test read(joinpath(figures, "plot-source.jl"))==read(joinpath(@__DIR__, "plot_r8_tradeoff.jl"))
end
