using Test, TOML, CSV, SHA
length(ARGS) in (2, 3) || error("usage: check_r9_numerics_figures.jl REPORT FIGURES [DOC_PNG]")
report, figures=abspath.(ARGS[1:2])
hashfile(p) = bytes2hex(sha256(read(p)))
@testset "R9 numerical figure source and independent residual aggregation" begin
    m=TOML.parsefile(joinpath(figures, "figure-config.toml"))
    @test m["schema"]=="r9-numerics-figure-v1" && m["origin"]=="synthetic"
    @test m["report_sha256"]==hashfile(joinpath(report, "report.toml"))
    for (p, h) in m["files"]
        @test hashfile(joinpath(figures, p))==h
    end
    for p in ("summary.csv", "trajectories.csv")
        @test read(joinpath(report, p))==read(joinpath(figures, p))
    end
    raw=NamedTuple[]
    for p in readdir(report)
        startswith(p, "residuals-") || continue
        append!(raw, NamedTuple.(CSV.File(joinpath(report, p); types = Dict(:entity=>String))))
    end
    for r in CSV.File(joinpath(figures, "residual-maxima.csv"))
        expected=maximum(
            x.residual/x.tolerance for x in raw if x.run_id==r.run_id && x.scope==r.scope
        )
        @test r.maximum_ratio==expected
    end
    length(ARGS)==3 && @test read(ARGS[3])==read(joinpath(figures, "F35-r9-numerics.png"))
end
