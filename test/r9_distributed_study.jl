module R9DistributedStudyTests
using Test, TOML, JuMP, Clarabel
include(joinpath(@__DIR__, "../scripts/r9_distributed_study.jl"))
const STUDY=R9DistributedStudy
const ROOT=normpath(joinpath(@__DIR__, ".."))

@testset "R9 distributed frozen mode rule and paired domains" begin
    data=Dict(
        "T"=>4,
        "grid_price"=>[10.0, 20.0, 30.0, 20.0],
        "devices"=>[Dict("kind"=>k) for k in ("PV", "BS", "HS")],
        "heat"=>Dict("pipes"=>[1, 2, 3]),
        "network_control"=>Dict("electric_initial"=>[1, 1, 0], "heat_initial"=>[1, 0, 1]),
    )
    original=deepcopy(data)
    modes=STUDY.input_modes((; data))
    @test data==original
    @test modes["z_storage"][1, :]==zeros(4)
    @test modes["z_storage"][2, :]==[1, 1, 0, 1]
    @test modes["z_storage"][3, :]==[1, 1, 0, 1]
    @test modes["heat_direction"]==repeat([1, 0, 1], 1, 4)
    @test all(modes["heat_direction"] .<= modes["u_H"])
    legacy=STUDY.input_modes((; data); version = 1)
    @test any(legacy["heat_direction"] .> legacy["u_H"])
    @test modes["u_E"]==repeat([1, 1, 0], 1, 4)
    @test modes["u_H"]==reshape([1, 0, 1], 3, 1)
    # 同一输入的模式不依赖历史候选；等价正价格换算保持规则。
    data["unused_candidate_cost"]=123.0
    @test STUDY.input_modes((; data))==modes
    data["grid_price"].*=1000
    @test STUDY.input_modes((; data))==modes
    p=STUDY.protocol(ROOT)
    @test length(p["methods"])==6
    @test length(STUDY.protocol(ROOT, "configs/r9/distributed-fixed-correction.toml")["methods"])==2
    @test length(STUDY.protocol(ROOT, "configs/r9/distributed-study.toml")["methods"])==6
    corridor=deepcopy(original)
    corridor["heat"]=Dict(
        "pipes"=>[Dict("from"=>a, "to"=>b) for (a, b) in ((3, 25), (25, 24), (24, 5))],
    )
    corridor["network_control"]["heat_initial"]=[1, 1, 1]
    version3=STUDY.input_modes((; data = corridor); version = 3)
    @test all(iszero, version3["heat_direction"])
    @test version3["z_storage"]==modes["z_storage"]
    corridor["network_control"]["heat_initial"][2]=0
    @test_throws ErrorException STUDY.input_modes((; data = corridor); version = 3)
    for entry in filter(x->x["method"]=="admm", p["methods"])
        peer=only(
            x for x in p["methods"] if
            x["method"]=="central" && x["case"]==entry["case"] && x["domain"]==entry["domain"]
        )
        @test peer["solver"]==entry["solver"]
    end
    factory=STUDY.optimizer(first(p["methods"]), p)
    @test Base.invokelatest(JuMP.MOI.instantiate, factory) isa JuMP.MOI.AbstractOptimizer
    mktempdir() do root
        write(joinpath(root, "manifest.toml"), "changed=true\n")
        target=joinpath(root, "new-study")
        @test_throws ErrorException STUDY.freeze(root, target)
        @test !ispath(target)
        @test_throws KeyError STUDY.check(root)
    end
end
end
