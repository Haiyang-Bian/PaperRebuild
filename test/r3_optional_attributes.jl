using Test

@testset "R3 optional solver attribute failures preserve evidence" begin
    got=PaperRebuild.r3_optional_attribute(()->2.0)
    @test got.value==2.0
    @test isnothing(got.error)
    for attr in ("ObjBound", "Pi")
        failure=PaperRebuild.r3_optional_attribute(
            ()->error("Gurobi Error 10005: Unable to retrieve attribute '$attr'"),
        )
        @test isnothing(failure.value)
        @test occursin(attr, failure.error)
    end
    @test_throws ErrorException PaperRebuild.r3_optional_attribute(
        ()->error("unexpected implementation failure"),
    )
end
