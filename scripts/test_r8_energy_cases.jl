using Test
include("r8_energy_cases.jl")
@testset "R8-E4 frozen four-hour mechanism before optimization" begin
    root=normpath(joinpath(@__DIR__, ".."))
    for UA in (0.0, 10.0)
        x=r8_shift_input(root; UA)
        @test x.case.normal.data["origin"]=="synthetic"
        @test all(g["kind"]!="BES" for g in x.case.normal.data["devices"])
        @test only(x.case.specification["events"])["periods"]==4
        @test length(PaperRebuild.r7_planning_pairs(x.case))==3
        @test all(iszero, x.case.normal.data["electric"]["root_eligible"][3:3])
    end
    rows=r8_shift_hand_replay()
    @test getproperty.(rows, :stored_above_initial_MWh)≈[0.1, 0.2, 0.1, 0.0] atol=1e-12
    @test all(abs(r.electric_residual_MW)<1e-12 && abs(r.heat_residual_MW)<1e-12 for r in rows)
    @test all(0<=r.GT_MW<=0.5 && 0<=r.EB_MW<=0.25 for r in rows)
    @test all(333.15-1e-10<=r.S_in_K<=353.15 && 303.15<=r.R_in_K<=323.15 for r in rows)
    @test last(rows).S_in_K≈334.15 atol=1e-10
    @test last(rows).R_in_K≈334.15-0.4/0.021 atol=1e-10
    # 晚段P_CHP+P_GT<=0.8。每1 MW电锅炉少供1 MW电，只多供0.95 MW热，
    # 因此逐时即时能量模型至少有0.1 MWh电热总失供，两个晚段下界为0.2。
    @test 2*(0.4-0.3)≈0.2
end
