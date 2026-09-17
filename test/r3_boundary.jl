using Test, JuMP
@testset "R3 comparable boundaries and old operation hashes" begin
    P=PaperRebuild
    for name in ("single-source", "two-source")
        c=load_r2_case(joinpath(@__DIR__, "..", "configs", "r3", name*"-four-modes-v1.toml"))
        old=R3OperationSpec(c; mode = :VF_CT)
        dictionary=P.r3_operation_dict(old)
        @test !haskey(dictionary, "tail_return_rule")
        @test P.r3_operation_dict(P.r3_operation_from_dict(dictionary))==dictionary
        @test P.r3_operation_dict(
            R3OperationSpec(
                old.mode,
                old.core_periods,
                old.reference_flow,
                old.source_temperature_K,
                old.bounded_return,
            ),
        )==dictionary
        bounded=R3OperationSpec(c; mode = :VF_CT, tail_return_rule = :bounded)
        @test P.r3_operation_hash(P.r3_operation_dict(bounded))!=P.r3_operation_hash(dictionary)
        @test P.r3_operation_dict(P.r3_operation_from_dict(P.r3_operation_dict(bounded))) ==
              P.r3_operation_dict(bounded)
        a=build_r3_subproblem(c, P.r2_flow_matrix(c); operation = old)
        b=build_r3_subproblem(c, P.r2_flow_matrix(c); operation = bounded)
        loads=count(n["role"]=="load" for n in c.data["heat"]["nodes"])
        @test length(a.constraints["R3-operation"])-length(b.constraints["R3-operation"]) ==
              loads*(c.data["T"]-old.core_periods)
        for key in keys(a.constraints)
            key=="R3-operation" && continue
            @test length(a.constraints[key])==length(b.constraints[key])
        end
        core=r3_boundary_case(c, :core_only)
        @test core.data["T"]==4
        @test P.r3_core_signature(core, 4)==P.r3_core_signature(c, 4)
        @test core.data["heat"]["pipes"][1]["S_history_K"]==c.data["heat"]["pipes"][1]["S_history_K"]
        @test r3_boundary_case(c, :bounded_return_tail)===c
        @test r3_boundary_case(c, :legacy_tail)===c
        @test_throws ArgumentError r3_boundary_case(c, :unknown)
        @test_throws ArgumentError R3OperationSpec(
            c;
            tail_return_rule = :bounded,
            bounded_return = false,
        )
    end
end
