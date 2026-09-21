using Test, TOML, CSV
include("report_r9_compact.jl")
const R=R9CompactReport
@testset "R9 matched protocols and actual PV accounting" begin
    a=TOML.parsefile("results/summaries/r9-seeded-input-20260921-v1/manifest.toml")
    b=TOML.parsefile("results/summaries/r9-compact-input-20260921-v1/manifest.toml")
    @test R.check_protocol(a, b)
    for change in (
        x->(x["cases"]["3A"]="other"),
        x->(x["protocol"]["budget_sec"]=601),
        x->(x["protocol"]["new_setting"]=1),
        x->(x["protocol"]["representation"]="original"),
        x->(x["protocol"]["solver_log"]=false),
    )
        c=deepcopy(b)
        change(c)
        @test_throws ErrorException R.check_protocol(a, c)
    end
    cases=[
        Dict(
            "id"=>"s$i",
            "probability"=>p,
            "case"=>Dict("dt_h"=>0.25, "devices"=>[Dict("kind"=>"PV"), Dict("kind"=>"CHP")]),
        ) for (i, p) in enumerate([0.25, 0.75])
    ]
    values=Dict(
        "scenarios"=>Dict(
            "s1"=>Dict("values"=>Dict("P_DER"=>[[1.0, 3.0], [100.0, 100.0]])),
            "s2"=>Dict("values"=>Dict("P_DER"=>[[2.0, 6.0], [100.0, 100.0]])),
        ),
    )
    @test R.pv_energy(cases, values)==1.75
    no_pv=deepcopy(cases)
    for c in no_pv
        c["case"]["devices"][1]["kind"]="CHP"
    end
    @test R.pv_energy(no_pv, values)==0
    bad=deepcopy(values)
    pop!(bad["scenarios"]["s1"]["values"]["P_DER"])
    @test_throws ErrorException R.pv_energy(cases, bad)
    mktempdir() do dir
        p=joinpath(dir, "empty.csv")
        R.csv_or_header(p, NamedTuple[], "scheme,cost")
        @test propertynames(CSV.File(p))==[:scheme, :cost]
        @test isempty(CSV.File(p))
    end
end
