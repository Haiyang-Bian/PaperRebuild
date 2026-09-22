module R6StudyReportTests
using Test
include(joinpath(@__DIR__, "..", "scripts", "r6_study_tables.jl"))

const c=Dict("id"=>"D", "method"=>"D", "radius"=>0.0)
function day(cost; complete = true, event = "pass")
    Dict{String,Any}(
        "model_pass"=>complete,
        "cost_complete"=>complete,
        "comfort_outcome"=>event,
        "operating_net_cost"=>cost,
        "delivery_budget_pass"=>true,
        "peak_excess_K"=>0.0,
        "called_energy_MWh"=>1.0,
        "mismatch_MWh"=>0.1,
    )
end

@testset "R6 saved evidence tables keep unknown and objective scope" begin
    r=r6_study_training_row(c, nothing)
    @test !r.record_available && r.status=="not_recorded"
    @test isnan(r.training_objective_USD) && isnan(r.elapsed_sec)
    s=r6_summarize_days(
        ["a", "b"],
        [day(-1), day(NaN; complete = false, event = "unknown")];
        epsilon = 0.05,
    )
    row=r6_study_summary_row("test", c, s, [Dict("candidate_id"=>"D", "validated"=>false)])
    @test row.n==2 && row.unknown==1 && row.missing_cost_days==1
    @test isnan(row.mean_net_cost_USD) && row.observed_mean_USD==-1
    @test row.selected_for_test && !row.selected_validation_eligible
    @test row.upper>=0.5 && row.risk_status!="supported"
    pending=r6_study_summary_row("validation", c, nothing, [])
    @test !pending.record_available && pending.risk_status=="not_recorded"
    unknown=r6_study_day_row(
        "test",
        c,
        "a",
        Dict("model_pass"=>false, "cost_complete"=>false, "comfort_outcome"=>"unknown"),
    )
    @test unknown.status=="no_accepted_training_policy" && isnan(unknown.net_cost_USD)
    @test isnan(unknown.call_relative_mismatch)
end

@testset "R6 paired test days exclude neither failure nor pending method" begin
    statistics=Dict("bootstrap_seed"=>12, "bootstrap_replicates"=>100, "confidence"=>0.95)
    b=Dict("id"=>"SP", "method"=>"SP", "radius"=>0.0)
    rows=[
        r6_study_day_row("test", z, id, day(cost)) for (z, cost) in [(c, 1.0), (b, 3.0)] for
        id in ["a", "b"]
    ]
    p=only(r6_study_pair_table(rows, ["D", "SP"], statistics))
    @test p.status=="complete_pairs" && p.n==2 && p.mean_difference_USD==-2
    @test p.lower_USD==p.upper_USD==-2
    failed=r6_study_day_row("test", b, "b", day(NaN; complete = false, event = "unknown"))
    rows[end]=failed
    p=only(r6_study_pair_table(rows, ["D", "SP"], statistics))
    @test p.status=="incomplete_pairs" && p.missing_pairs==1
    @test isnan(p.mean_difference_USD) && isnan(p.lower_USD)
    @test isempty(r6_study_pair_table(rows, ["absent", "D"], statistics))
    @test isempty(r6_study_pair_table(rows, ["D", "absent"], statistics))
    @test isempty(
        r6_study_pair_table(
            [merge(r, (split = "validation",)) for r in rows],
            ["D", "SP"],
            statistics,
        ),
    )
end

@testset "R6 table chunk completeness and numeric serialization" begin
    rows=[(id = i, unit = "USD", value = Float64(i)) for i in 1:5001]
    files=r6_study_table_bytes(Dict("days"=>rows, "empty"=>NamedTuple[]))
    @test Set(keys(files))==Set(["days-001.csv", "days-002.csv"])
    firstrows=collect(CSV.File(files["days-001.csv"]))
    lastrows=collect(CSV.File(files["days-002.csv"]))
    @test length(firstrows)==5000 && length(lastrows)==1
    @test firstrows[end].id==5000 && lastrows[1].id==5001
    @test lastrows[1].value==5001.0 && lastrows[1].unit=="USD"
    @test r6_study_table_bytes(Dict("days"=>rows))==files
end
end
