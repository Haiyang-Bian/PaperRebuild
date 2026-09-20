using Test
include("audit_r8_energy.jl")
length(ARGS)==3 || error("usage: check_r8_energy_results.jl REPORT PARENT AUDIT")
report, parentdir, audit=abspath.(ARGS)
x=r8_energy_archive(report)
parent=r8_archive_check(parentdir)
a=TOML.parsefile(joinpath(audit, "audit.toml"))
csvbytes(xs) = sprint(io->CSV.write(io, xs))
@testset "R8 energy frozen values, same-input contrasts and analytic bounds" begin
    @test a["origin"]=="synthetic"
    @test a["report_manifest_sha256"]==r8_file_hash(joinpath(report, "report-hashes.toml"))
    @test a["parent_manifest_sha256"]==r8_file_hash(joinpath(parentdir, "report-hashes.toml"))
    actual=r8_archive_files(audit)
    delete!(actual, "audit.toml")
    @test actual==a["files"]
    @test read(joinpath(audit, "audit-source.jl"))==read(joinpath(@__DIR__, "audit_r8_energy.jl"))
    @test read(joinpath(report, "summary.csv"), String)==csvbytes(r8_energy_tables(x))
    rr=r8e_residuals(x)
    @test length(rr)==a["residual_count"]
    for (i, p) in enumerate(a["residual_parts"])
        k=5000(i-1)+1
        @test read(joinpath(audit, p), String)==csvbytes(rr[k:min(k+4999, length(rr))])
    end
    pairs=r8e_pairs(x)
    @test length(pairs)==18
    @test all(z.judgement!="contradiction" for z in pairs)
    for (p, rows) in (
        ("solver-pairs.csv", pairs),
        ("model-comparisons.csv", r8e_model_comparisons(x, parent)),
        ("trajectories.csv", r8e_trajectories(x)),
        ("boundary-certificates.csv", r8e_boundaries(x)),
    )
        @test read(joinpath(audit, p), String)==csvbytes(rows)
    end
    for row in r8_energy_tables(x)
        @test row.elapsed_sec<=x.rule["budget_sec"] && row.wall_budget_pass
        @test !row.primary_complete || row.primary_pass
        @test !row.risk_complete || row.evaluation_pass
        if row.primary_status=="infeasible_certified"
            @test ismissing(row.normal_cost_USD)
        end
    end
    # 针对预先推导的解析边界核验，失败原值仍保留，不能靠跳过来产生通过结论。
    for c in r8e_boundaries(x)
        r=x.records[c.id].result
        if c.certificate=="isolated_CHP_no_electric_sink"
            stage=r["primary"]["evaluation"] ? r["primary"] :
                  r["primary"]["status"]=="candidate" ? r["evaluation"] : r["primary"]
            @test stage["status"]=="infeasible_certified"
        else
            if r["validation"]["primary_model_pass"]
                ev=r["validation"]["evaluation"]
                @test ev["model_pass"] && ev["objective_complete"]
                @test only(ev["event_upper_MWh"])≈c.value atol=1e-6
                @test only(ev["event_lower_MWh"])≈c.value atol=1e-6
            else
                @test r["primary"]["status"]=="infeasible_certified"
            end
        end
    end
    traces=r8e_trajectories(x)
    for z in traces
        if z.model=="detailed"
            @test abs(z.cumulative_energy_residual_MWh)<=1e-6
            @test abs(z.replay_temperature_error_K)<=1e-4
        else
            @test ismissing(z.stored_above_initial_MWh)
        end
    end
    for item in x.items
        item["family"]=="shift_four"&&item["model"]=="detailed" || continue
        q=x.records[item["id"]].validation
        @test q["primary_model_pass"] && q["recovery_verified"]
        @test maximum(abs.(q["evaluation"]["event_upper_MWh"]))<=1e-6
    end
    println(
        "Verified ",
        length(x.items),
        " records, ",
        length(rr),
        " residuals, 18 solver pairs and ",
        length(traces),
        " trajectory rows.",
    )
end
