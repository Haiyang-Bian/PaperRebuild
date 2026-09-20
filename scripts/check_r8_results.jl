using Test
include("audit_r8_results.jl")
length(ARGS)==2||error("usage: check_r8_results.jl REPORT AUDIT")
report, audit=abspath.(ARGS)
x=r8_archive_check(report)
a=TOML.parsefile(joinpath(audit, "audit.toml"))
function r8_csv_bytes(rows)
    io=IOBuffer()
    CSV.write(io, rows)
    take!(io)
end
@testset "R8 immutable raw values and independent attribution" begin
    @test a["origin"]=="synthetic"
    @test a["report_manifest_sha256"]==r8_file_hash(joinpath(report, "report-hashes.toml"))
    actual=r8_archive_files(audit)
    delete!(actual, "audit.toml")
    @test actual==a["files"]
    @test read(joinpath(audit, "audit-source.jl"))==read(joinpath(@__DIR__, "audit_r8_results.jl"))
    t=r8_study_tables(x)
    @test length(t.rows)==x.rule["record_count"]==34
    @test read(joinpath(report, "summary.csv"))==r8_csv_bytes(t.rows)
    @test read(joinpath(report, "events.csv"))==r8_csv_bytes(t.events)
    rr=r8_residual_table(x)
    @test length(rr)==a["residual_count"]
    @test length(a["residual_parts"])==cld(length(rr), 5000)
    for (k, p) in enumerate(a["residual_parts"])
        firstrow=5000(k-1)+1
        @test read(joinpath(audit, p))==r8_csv_bytes(rr[firstrow:min(firstrow+4999, length(rr))])
    end
    comparisons=r8_comparison_table(x)
    @test read(joinpath(audit, "comparisons.csv"))==r8_csv_bytes(comparisons)
    @test all(r->r.judgement!="contradiction", comparisons)
    heat=r8_heat_boundary_table(x)
    @test read(joinpath(audit, "heat-boundary.csv"))==r8_csv_bytes(heat)
    @test all(r->r.infeasibility_supported, heat)
    for row in t.rows
        r=x.records[row.id].result
        @test row.wall_budget_pass
        @test row.elapsed_sec<=x.rule["budget_sec"]
        @test row.primary_model_pass==r["validation"]["primary_model_pass"]
        if row.objective_complete
            @test row.primary_model_pass
            @test row.relative_gap<=1e-4
        end
        if row.risk_complete
            @test row.evaluation_pass
        end
        # 失败和限时仍是正式记录，不要求所有结果成功。
        if row.primary_status=="infeasible_certified"
            @test !row.primary_model_pass
            @test ismissing(row.normal_cost_USD)
        end
    end
    println(
        "R8 preserved ",
        length(t.rows),
        " records and ",
        length(rr),
        " residuals; ",
        count(r->r.primary_model_pass, t.rows),
        " primary candidates, ",
        count(r->r.objective_complete, t.rows),
        " completed primary objectives, ",
        count(r->r.evaluation_pass, t.rows),
        " independently verified recovery evaluations.",
    )
end
