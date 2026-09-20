using Test, TOML, CSV, SHA
include("r9_pv_study.jl")
length(ARGS)==2 || error("usage: check_r9_pv_results.jl BATCH REPORT")
batch, report=abspath.(ARGS)
@testset "R9 original values, terminal memory, comparison and tamper rejection" begin
    saved=TOML.parsefile(joinpath(report, "report.toml"))
    if saved["schema"]=="r9-pv-report-v2"
        @test saved["source_batch"]==basename(batch)
        @test !isabspath(saved["source_batch"])
    end
    @test saved["batch_manifest_sha256"]==R9PVStudy.hashfile(joinpath(batch, "manifest.toml"))
    for (p, h) in saved["files"]
        @test R9PVStudy.hashfile(joinpath(report, p))==h
    end
    mktempdir() do dir
        fresh=joinpath(dir, "replay")
        loader=Module(gensym(:R9ReportReplay))
        Base.include(loader, joinpath(report, "report-source.jl"))
        Base.invokelatest(()->getfield(getfield(loader, :R9PVStudy), :report)(batch, fresh))
        for p in keys(saved["files"])
            @test read(joinpath(report, p))==read(joinpath(fresh, p))
        end
    end
    rows=collect(CSV.File(joinpath(report, "summary.csv")))
    @test length(rows)==6
    for mode in ("CF_CT", "CF_VT")
        a=only(r for r in rows if r.mode==mode && r.solver=="Clarabel")
        b=only(r for r in rows if r.mode==mode && r.solver=="Gurobi" && !r.physical_model)
        if a.model_pass && b.model_pass
            @test abs(a.cost_CNY-b.cost_CNY)/max(1, abs(a.cost_CNY), abs(b.cost_CNY))<=1e-4
        end
    end
    f=R9PVStudy.frozen(batch)
    for entry in f.manifest["entries"]
        r=TOML.parsefile(joinpath(batch, "runs", entry["id"], "result.toml"))
        haskey(r["stage"], "values") || continue
        bad=deepcopy(r)
        haskey(bad, "reconstructed") && delete!(bad, "reconstructed")
        bad["stage"]["values"]["tau_R_in"][1][end]+=0.1
        v=Base.invokelatest(()->getfield(f.mod, :validate_r9_pv_solution)(f.c, bad))
        @test !v.terminal_pass
        @test !v.physical_pass
    end
end
