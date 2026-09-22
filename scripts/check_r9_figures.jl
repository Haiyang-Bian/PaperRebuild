using Test, CSV, TOML, SHA
include("r9_source_report.jl")
length(ARGS) in (2, 3) || error("usage: check_r9_figures.jl REPORT FIGURES [DOC_PNG]")
report, figures=abspath.(ARGS[1:2])
@testset "R9 topology figure sources and literal node identities" begin
    R9SourceReport.check_report(report)
    c=TOML.parsefile(joinpath(figures, "figure-config.toml"))
    @test c["schema"]=="r9-source-figure-v1" && !c["optimization_performed"]
    @test c["report_manifest_sha256"]==R9SourceReport.hashfile(joinpath(report, "manifest.toml"))
    for (name, hash) in c["files"]
        @test R9SourceReport.hashfile(joinpath(figures, name))==hash
    end
    nodes=collect(CSV.File(joinpath(figures, "nodes.csv")))
    edges=collect(CSV.File(joinpath(figures, "edges.csv")))
    g=TOML.parsefile(joinpath(report, "topology.toml"))
    d=TOML.parsefile(joinpath(report, "inputs.toml"))
    for side in ("electric", "heat")
        ns=filter(r->r.network==side, nodes)
        @test length(ns)==g[side]["nodes"]
        @test Set(r.node for r in ns)==Set(1:g[side]["nodes"])
        @test all(r->isfinite(r.x)&&isfinite(r.y)&&r.layout_unit=="schematic", ns)
        expected=Set(Tuple(e) for e in g[side]["edges"])
        @test Set((r.from, r.to) for r in edges if r.network==side && r.status!="trading_tie")==expected
        @test Set((r.from, r.to) for r in edges if r.network==side && r.status=="trading_tie")==Set(
            Tuple(e) for e in d["trading"]["new_$(side)_ties"]
        )
    end
    @test length(edges)==86
    @test Set((r.from, r.to) for r in edges if r.status=="upstream_feeder")==Set(
        Tuple(e) for e in g["electric"]["upstream_feeders"]
    )
    if length(ARGS)==3
        @test R9SourceReport.hashfile(ARGS[3])==c["files"]["F33-r9-topology.png"]
    end
end
