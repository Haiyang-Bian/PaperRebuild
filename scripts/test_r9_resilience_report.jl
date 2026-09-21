using Test, TOML
include("r9_resilience_evidence.jl")
const Evidence=R9ResilienceEvidence
@testset "R9-RW3 independent capacity certificate" begin
    d=Dict(
        "schema"=>"r7-recovery-case-v1",
        "probabilities"=>[1.0],
        "dt_h"=>0.5,
        "periods"=>2,
        "load_service"=>Dict("critical_load_MW"=>[[4.0, 6.0]]),
        "renewable_factor"=>0.5,
        "devices"=>[
            Dict("kind"=>"CHP", "P_max_MW"=>4.0, "commitment"=>[0, 1]),
            Dict("kind"=>"GT", "P_max_MW"=>1.0),
            Dict("kind"=>"PV", "available_MW"=>[[2.0], [4.0]]),
            Dict("kind"=>"EB", "P_max_MW"=>10.0),
        ],
    )
    q=Evidence.capacity_certificate(d)
    @test q.critical_MWh==5.0
    @test q.generation_upper_MWh==4.5
    @test q.unserved_lower_MWh==1.0
    @test q.unserved_lower_MWh>max(0, q.critical_MWh-q.generation_upper_MWh)
    @test [r.generation_upper_MW for r in q.rows]==[2.0, 7.0]
    e=deepcopy(d)
    e["devices"][1]["commitment"]=[1, 1]
    @test Evidence.capacity_certificate(e).unserved_lower_MWh==0
    e=deepcopy(d)
    push!(e["devices"], Dict("kind"=>"BES", "P_max_MW"=>1.0))
    @test_throws ErrorException Evidence.capacity_certificate(e)
    e=deepcopy(d)
    e["probabilities"]=[0.5, 0.5]
    @test_throws ErrorException Evidence.capacity_certificate(e)
    e=deepcopy(d)
    e["dt_h"]=0.25
    e["periods"]=4
    e["load_service"]["critical_load_MW"]=[
        repeat(x; inner = 2) for x in e["load_service"]["critical_load_MW"]
    ]
    e["devices"][1]["commitment"]=repeat(e["devices"][1]["commitment"]; inner = 2)
    e["devices"][3]["available_MW"]=repeat(e["devices"][3]["available_MW"]; inner = 2)
    z=Evidence.capacity_certificate(e)
    @test (z.critical_MWh, z.generation_upper_MWh, z.unserved_lower_MWh)==(5.0, 4.5, 1.0)
    for p in ("../escape", "/absolute", "C:/absolute", "a\\b", "a/./b", "")
        @test_throws ErrorException Evidence.safe(@__DIR__, p)
    end
end
if !isempty(ARGS)
    length(ARGS)==1 || error("usage: test_r9_resilience_report.jl [EVIDENCE]")
    folder=abspath(only(ARGS))
    @testset "Frozen evidence byte tampering" begin
        @test Evidence.check(folder)
        temp=mktempdir(joinpath(dirname(@__DIR__), "tmp"); cleanup = false)
        mkpath(joinpath(temp, "objects"))
        h=first(readdir(joinpath(folder, "objects")))
        bytes=read(joinpath(folder, "objects", h))
        bytes[1] ⊻= 0x01
        write(joinpath(temp, "objects", h), bytes)
        @test_throws ErrorException Evidence.Objects.bytes(temp, h)
        @test Evidence.Objects.bytes(folder, h)==read(joinpath(folder, "objects", h))
    end
    using CSV
    summary=collect(CSV.File(joinpath(folder, "summary.csv")))
    residuals=collect(CSV.File(joinpath(folder, "residuals.csv")))
    if hasproperty(first(residuals), :scope)
        @testset "Adopted feasibility does not erase exact-exchange failures" begin
            @test count(r->r.model_pass, summary)==7
            diagnostic=filter(r->r.scope=="exact_exchange", residuals)
            @test length(diagnostic)==3
            @test all(r->r.maximum_normalized>1 && !r.all_pass, diagnostic)
            @test all(r->r.all_pass, filter(r->r.scope=="adopted", residuals))
            @test all(
                r->r.exact_exchange_check=="false",
                filter(r->startswith(r.stage, "aggregate-"), summary),
            )
        end
    end
end
