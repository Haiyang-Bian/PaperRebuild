using Test
include("r7_normal_evidence.jl")

function test_r7_normal_evidence(bundle)
    @testset "R7-D6 isolated committed CHP and saved evidence" begin
        x=r7_normal_evidence(["check", bundle])
        summary=TOML.parsefile(joinpath(bundle, "summary.toml"))
        @test summary["normal_cost_USD"]≈118.4
        @test summary["normal_model_pass"] &&
              summary["conditional_cost_complete"] &&
              summary["normal_pipe_reference_pass"]
        @test !summary["complete_R7_verified"] && !summary["full_preplan_optimality_verified"]
        @test summary["event_records"]==2 && summary["event_model_pass"]==1
        continuation=TOML.parsefile(joinpath(bundle, "continuation.toml"))
        @test continuation["original_run_files_identical"] && !continuation["reoptimized"]
        good, bad=x.runs
        @test good.validation["loss_MWh"]≈0.0 atol=1e-6
        @test bad.result["status"]=="infeasible_certified" && !bad.validation["model_pass"]
        # 冻结反例：内部唯一电线断开、PCC断开，CHP孤岛没有任何消纳端。
        d=x.event_case.data
        chp=only(g for g in d["devices"] if g["electric_node"]==1)
        @test chp["kind"]=="CHP" && chp["P_min_MW"]>0 && all(==(1), chp["commitment"])
        @test all(iszero, d["electric"]["load_MW"][1])
        @test length(d["electric"]["lines"])==1 && bad.result["fault"]==[1]
        normal=x.normal.case.data
        @test normal["heat_terminal_rule"]=="pipe_inventory_initial" && normal["periods"]==4
        @test sum(sum(row) for row in normal["heat"]["load_MW"])*normal["dt_h"]>3chp["P_max_MW"]*chp["heat_ratio"]*normal["dt_h"]
        # 不可行没有失供数值；不能将缺失值绘成“零失供”。
        events=collect(CSV.File(joinpath(bundle, "event-summary.csv")))
        @test ismissing(events[2].loss_MWh)
        root=normpath(joinpath(@__DIR__, ".."))
        mkpath(joinpath(root, "tmp"))
        mktempdir(joinpath(root, "tmp")) do temp
            copydir=joinpath(temp, "evidence")
            cp(bundle, copydir)
            summarypath=joinpath(copydir, "summary.toml")
            original=read(summarypath, String)
            write(summarypath, "")
            @test_throws ErrorException r7_normal_evidence(["check", copydir])
            open(joinpath(copydir, "evidence-files.toml"), "w") do io
                TOML.print(io, Dict("files"=>r7_evidence_hashes(copydir)); sorted = true)
            end
            @test_throws ErrorException r7_normal_evidence(["check", copydir])
            write(summarypath, replace(original, "118.4"=>"118.5"))
            open(joinpath(copydir, "evidence-files.toml"), "w") do io
                TOML.print(io, Dict("files"=>r7_evidence_hashes(copydir)); sorted = true)
            end
            @test_throws ErrorException r7_normal_evidence(["check", copydir])
        end
    end
end

abspath(PROGRAM_FILE)==(@__FILE__) && test_r7_normal_evidence(only(ARGS))
