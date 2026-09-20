using Test
include("audit_r8_results.jl")

@testset "R8-T6 normal heat boundary certificate" begin
    rule=TOML.parsefile(joinpath(R8_ROOT, "configs/r8/tradeoff-study.toml"))
    items=r8_study_records(rule)
    rows=r8_heat_boundary_table((; items))
    @test length(rows)==4
    @test all(r->r.infeasibility_supported, rows)
    @test all(r->r.deficit_K>0.018 && r.inventory_deficit_MWh>3.9e-4, rows)
    @test all(r->isapprox(r.return_end_upper_K, r.replay_return_K; atol = 1e-9), rows)
    for r in rows
        println(r)
    end
    lossless=deepcopy(filter(x->x["resource"]=="no_net_heat_charge", items))
    for x in lossless, p in x["normal"]["heat"]["pipes"]
        p["UA_S_W_K"]=0.0
        p["UA_R_W_K"]=0.0
    end
    z=r8_heat_boundary_table((; items = lossless))
    @test all(r->!r.infeasibility_supported && abs(r.deficit_K)<1e-10, z)
    too_short=deepcopy(lossless)
    first(too_short)["normal"]["periods"]=1
    @test_throws ErrorException r8_heat_boundary_table((; items = too_short))
    mismatched=deepcopy(lossless)
    first(mismatched)["normal"]["heat"]["pipes"][1]["UA_R_W_K"]=1.0
    @test_throws ErrorException r8_heat_boundary_table((; items = mismatched))
end
