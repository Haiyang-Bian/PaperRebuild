using Test, CSV, TOML, SHA
length(ARGS) in (2, 3) || error("usage: check_r7_flow_planning_figures.jl REPORT FIGURES [DOC_PNG]")
report, figures=abspath.(ARGS[1:2])
hashfile(p) = bytes2hex(sha256(read(p)))
config=TOML.parsefile(joinpath(figures, "figure.toml"))
registry=TOML.parsefile(joinpath(report, "report-hashes.toml"))["files"]
@testset "R7 shared flow figure sources and units" begin
    @test config["origin"]=="synthetic"
    @test config["figure"]=="F29"
    @test Set(config["units"])==Set(["USD", "MWh", "kg/s", "residual / tolerance"])
    for (p, h) in config["report_hashes"]
        @test h==registry[p]
        @test h==hashfile(joinpath(report, p))==hashfile(joinpath(figures, p))
    end
    @test config["run_ids"]==[r.run_id for r in CSV.File(joinpath(report, "summary.csv"))]
    @test config["plot_source_sha256"]==hashfile(joinpath(figures, "plot-source.jl"))
    for (p, h) in config["outputs"]
        @test hashfile(joinpath(figures, p))==h
    end
    length(ARGS)==3&&(@test hashfile(abspath(ARGS[3]))==config["outputs"]["F29-shared-flow.png"])
end
