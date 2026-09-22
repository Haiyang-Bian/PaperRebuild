using Test, TOML, CSV
include("r9_pv_study.jl")
length(ARGS)==2 || error("usage: check_r9_presolve.jl BATCH DIAGNOSTIC")
batch, out=abspath.(ARGS)
@testset "R9 presolve diagnostic raw-value replay" begin
    f=R9PVStudy.frozen(batch)
    m=TOML.parsefile(joinpath(out, "manifest.toml"))
    @test m["parent_manifest_sha256"]==R9PVStudy.hashfile(joinpath(batch, "manifest.toml"))
    @test m["parameter"]==Dict("Presolve"=>0)
    evidence=TOML.parsefile(joinpath(out, "evidence.toml"))
    for (p, h) in evidence["files"]
        @test R9PVStudy.hashfile(joinpath(out, p))==h
    end
    rows=collect(CSV.File(joinpath(out, "summary.csv")))
    @test length(rows)==4
    for row in rows
        r=TOML.parsefile(joinpath(out, row.id*".toml"))
        @test r["solver_attributes"]==Dict("Presolve"=>0)
        v=Base.invokelatest(()->getfield(f.mod, :validate_r9_pv_solution)(f.c, r))
        @test v.model_pass==row.model_pass
        @test v.physical_pass==row.physical_pass
        @test v.terminal_pass==row.terminal_pass
        @test r["stage"]["status"]==row.status
        if haskey(r["stage"], "operating_cost")
            @test r["stage"]["operating_cost"]==row.cost_CNY
        else
            @test ismissing(row.cost_CNY)
        end
    end
end
