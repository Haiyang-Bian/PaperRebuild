using Test
include("r8_energy_study.jl")
@testset "R8 energy study frozen input and factor separation" begin
    rule=TOML.parsefile(joinpath(R8_ROOT, "configs/r8/energy-flow-study.toml"))
    xs=r8_energy_records(rule)
    @test length(xs)==length(unique(x["id"] for x in xs))==36
    @test count(x->x["family"]=="shift_four", xs)==24
    @test count(x->x["model"]=="detailed", xs)==12
    @test count(x->x["solver"]=="Gurobi", xs)==18
    @test all(x["normal"]["origin"]=="synthetic" for x in xs)
    for x in xs
        other=only(
            filter(
                y->y["family"]==x["family"]&&y["UA_W_K"]==x["UA_W_K"]&&y["model"]==x["model"]&&y["mode"]==x["mode"]&&y["solver"]!=x["solver"],
                xs,
            ),
        )
        @test x["case_sha256"]==other["case_sha256"]
        @test x["spec_sha256"]==other["spec_sha256"]
        if x["family"]=="shift_four"
            other_model=only(
                filter(
                    y->y["family"]==x["family"]&&y["UA_W_K"]==x["UA_W_K"]&&y["model"]!=x["model"]&&y["mode"]==x["mode"]&&y["solver"]==x["solver"],
                    xs,
                ),
            )
            @test x["case_sha256"]==other_model["case_sha256"]
        end
    end
    bad=deepcopy(rule)
    bad["new_CHP_max_MW"]=0.4
    @test_throws ErrorException r8_energy_records(bad)
end
