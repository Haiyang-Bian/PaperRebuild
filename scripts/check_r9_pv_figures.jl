using Test, TOML, CSV, SHA
length(ARGS) in (2, 3) || error("usage: check_r9_pv_figures.jl REPORT FIGURES [DOC_PNG]")
report, figures=abspath.(ARGS[1:2])
hashfile(p) = bytes2hex(sha256(read(p)))
@testset "R9 PV saved figure provenance" begin
    m=TOML.parsefile(joinpath(figures, "figure-config.toml"))
    @test m["schema"]=="r9-pv-figure-v1"
    @test m["origin"]=="synthetic"
    @test m["report_sha256"]==hashfile(joinpath(report, "report.toml"))
    for (p, h) in m["files"]
        @test hashfile(joinpath(figures, p))==h
    end
    for p in ("summary.csv", "trajectories.csv")
        @test read(joinpath(report, p))==read(joinpath(figures, p))
    end
    table=collect(CSV.File(joinpath(figures, "summary.csv")))
    @test all(id in getproperty.(table, :id) for id in m["selected_runs"])
    length(ARGS)==3 && @test read(ARGS[3])==read(joinpath(figures, "F34-r9-pv.png"))
end
