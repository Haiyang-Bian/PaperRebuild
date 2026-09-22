using Test, CSV, TOML, SHA
length(ARGS)==4 || error("usage: check_r8_energy_figures.jl REPORT AUDIT FIGURES DOCUMENT_IMAGE")
report, audit, figures, docimage=abspath.(ARGS)
hashfile(p) = bytes2hex(sha256(read(p)))
f=TOML.parsefile(joinpath(figures, "figure.toml"))
a=TOML.parsefile(joinpath(audit, "audit.toml"))
@testset "R8 F32 immutable sources, run identity and independent replay" begin
    @test f["origin"]=="synthetic"
    @test f["report_manifest_sha256"]==hashfile(joinpath(report, "report-hashes.toml"))
    @test f["audit_sha256"]==hashfile(joinpath(audit, "audit.toml"))
    @test Set(readdir(figures))==union(Set(keys(f["files"])), Set(["figure.toml"]))
    for (p, h) in f["files"]
        @test hashfile(joinpath(figures, p))==h
    end
    for p in ("summary.csv", "hand-witness.csv")
        @test read(joinpath(figures, p))==read(joinpath(report, p))
    end
    summary=collect(CSV.File(joinpath(report, "summary.csv")))
    @test f["run_ids"]==[r.run_id for r in summary]
    raw=collect(CSV.File(joinpath(audit, "trajectories.csv"); types = Dict(:fault=>String)))
    selected=collect(
        CSV.File(joinpath(figures, "selected-trajectories.csv"); types = Dict(:fault=>String)),
    )
    @test length(selected)==8
    for row in selected
        expected=only(
            filter(
                z->z.id==row.id&&z.event==row.event&&z.fault==row.fault&&z.scenario==row.scenario&&z.t==row.t,
                raw,
            ),
        )
        @test isequal(NamedTuple(row), NamedTuple(expected))
        @test row.terminal_rule=="recovery_free_thermal_end"
    end
    residuals=vcat([collect(CSV.File(joinpath(audit, p))) for p in a["residual_parts"]]...)
    for p in CSV.File(joinpath(figures, "residual-points.csv"))
        rr=filter(r->r.id==p.id, residuals)
        ratio=maximum(
            r.tolerance>0 ? r.residual/r.tolerance : r.residual==0 ? 0.0 : Inf for r in rr
        )
        @test p.residual_ratio==ratio
        @test summary[p.index].id==p.id&&summary[p.index].run_id==p.run_id
    end
    png=read(joinpath(figures, "F32-r8-energy.png"))
    @test png==read(docimage)
    be32(b) = foldl((x, y)->(x<<8)|UInt32(y), b; init = UInt32(0))
    @test Int[be32(png[17:20]), be32(png[21:24])]==f["size_pixels"]
    @test read(joinpath(figures, "plot-source.jl"))==read(joinpath(@__DIR__, "plot_r8_energy.jl"))
end
