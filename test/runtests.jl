using Test
using PaperRebuild

@testset "Package scaffold (not thesis validation)" begin
    @test PaperRebuild.hello("Julia") == "Hello, Julia"
    @test PaperRebuild.domath(2) == 7
    @test PaperRebuild.domath(1.5) == 6.5
end
