using Test, CSV, TOML, SHA
length(ARGS) in (3, 4)||error(
    "usage: check_r7_lossy_flow_figures.jl REPORT AUDIT FIGURES [DOC_PNG]",
)
report, audit, figures=abspath.(ARGS[1:3])
hashfile(p) = bytes2hex(sha256(read(p)))
c=TOML.parsefile(joinpath(figures, "figure.toml"))
registry=TOML.parsefile(joinpath(report, "report-hashes.toml"))["files"]
ac=TOML.parsefile(joinpath(audit, "audit.toml"))
@testset "R7 lossy F30 sources, scope and original bytes" begin
    @test c["origin"]=="synthetic"
    @test c["figure"]=="F30"
    @test Set(c["units"])==Set(["USD", "MWh", "kg/s", "W/K", "percent", "residual / tolerance"])
    for (p, h) in c["report_hashes"]
        @test h==registry[p]==hashfile(joinpath(report, p))==hashfile(joinpath(figures, p))
    end
    for (p, h) in c["audit_hashes"]
        @test h==ac["files"][p]==hashfile(joinpath(audit, p))==hashfile(joinpath(figures, p))
    end
    @test c["run_ids"]==[r.run_id for r in CSV.File(joinpath(report, "summary.csv"))]
    @test c["plot_source_sha256"]==hashfile(joinpath(figures, "plot-source.jl"))
    for (p, h) in c["outputs"]
        @test hashfile(joinpath(figures, p))==h
    end
    length(ARGS)==4&&(@test hashfile(abspath(ARGS[4]))==c["outputs"]["F30-lossy-flow.png"])
end
