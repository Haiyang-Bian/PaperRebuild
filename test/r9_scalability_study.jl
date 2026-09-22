module R9ScalabilityStudyTests
using Test, TOML, JuMP, Clarabel, PaperRebuild
include(joinpath(@__DIR__, "../scripts/r9_scalability_study.jl"))
include(joinpath(@__DIR__, "../scripts/run_r9_scalability_batch.jl"))
include("fixtures/r9_trading.jl")
const STUDY=R9ScalabilityStudy
const BATCH=R9ScalabilityBatch
const ROOT=normpath(joinpath(@__DIR__, ".."))

@testset "F13 frozen method identities and identical solver precision" begin
    p=TOML.parsefile(joinpath(ROOT, STUDY.PROTOCOL))
    @test STUDY.validate_protocol(p)===p
    @test length(p["methods"])==12
    @test length(STUDY.input_paths())==8 && allunique(STUDY.input_paths())
    for key in ("budget_sec", "archive_reserve_sec", "rho", "max_iterations")
        bad=deepcopy(p)
        bad[key]+=1
        @test_throws ErrorException STUDY.validate_protocol(bad)
    end
    for key in (
        "central_solution_injected",
        "author_input_equivalence",
        "author_algorithm_equivalence",
        "legacy_runtime_comparable",
    )
        bad=deepcopy(p)
        bad[key]=true
        @test_throws ErrorException STUDY.validate_protocol(bad)
    end
    bad=deepcopy(p)
    bad["methods"][1]["id"], bad["methods"][2]["id"]=bad["methods"][2]["id"],
    bad["methods"][1]["id"]
    @test_throws ErrorException STUDY.validate_protocol(bad)
    bad=deepcopy(p)
    bad["clarabel"]["tol_feas"]=1e-8
    @test_throws ErrorException STUDY.validate_protocol(bad)
    for key in ("archive", "timing")
        bad=deepcopy(p)
        bad[key]="unrecorded"
        @test_throws ErrorException STUDY.validate_protocol(bad)
    end
end

@testset "F13 one original trajectory roundtrip still needs mathematical replay" begin
    c=r9_trading_fixture(; store = true)
    modes=Dict(
        "z_storage"=>ones(Int, length(c.data["devices"]), c.data["T"]),
        "heat_direction"=>ones(Int, length(c.data["heat"]["pipes"]), c.data["T"]),
    )
    optimizer=optimizer_with_attributes(
        Clarabel.Optimizer,
        "tol_feas"=>1e-10,
        "tol_gap_abs"=>1e-10,
        "tol_gap_rel"=>1e-10,
    )
    mktempdir() do dir
        original=joinpath(dir, "original.toml")
        sha=Ref("")
        r=solve_r9_distributed(
            c;
            optimizer,
            modes,
            budget_sec = 60,
            deadline = PaperRebuild.r3_clock()+60,
            objective_record = :separate,
            on_raw_result = x->(sha[]=STUDY.save_raw(original, x)),
        )
        raw=TOML.parsefile(original)
        @test !haskey(raw, "validation") && !isempty(raw["trace"])
        @test sha[]==STUDY.hashfile(original)
        @test_throws ErrorException STUDY.save_raw(original, r)
        final=joinpath(dir, "completion.toml")
        STUDY.save_raw(final, STUDY.completion(r))
        reread=STUDY.apply_completion(raw, TOML.parsefile(final))
        @test isequal(reread, r)
        @test isequal(validate_r9_distributed(c, reread), r["validation"])
        @test r["validation"]["consensus_A4_pass"] && r["validation"]["best_model_found"]
        for key in ("status", "trace", "best_model_iteration")
            bad=STUDY.completion(r)
            bad[key]=r[key]
            @test_throws ErrorException STUDY.apply_completion(raw, bad)
        end
        for t in (-1.0, NaN, Inf)
            bad=STUDY.completion(r)
            bad["elapsed_sec"]=t
            @test_throws ErrorException STUDY.apply_completion(raw, bad)
        end
        bad=deepcopy(reread)
        bad["trace"][1]["x"][1][1]+=0.01
        # 即使重新签署文件哈希，改变控制/消息仍不能通过独立数学核验。
        altered=joinpath(dir, "resigned.toml")
        @test STUDY.save_raw(altered, bad)==STUDY.hashfile(altered)
        @test_throws ErrorException validate_r9_distributed(c, TOML.parsefile(altered))
        p=TOML.parsefile(joinpath(ROOT, STUDY.PROTOCOL))
        # 此处使用小例实际预算/迭代上限，只检验记录和调用规则的绑定，不运行规模模型。
        p["budget_sec"]=r["budget_sec"]
        p["archive_reserve_sec"]=0
        p["max_iterations"]=r["max_iterations"]
        entry=p["methods"][2]
        @test STUDY.check_result_rules(r, entry, p)
        for key in ("rho", "max_iterations", "budget_sec")
            bad=deepcopy(r)
            bad[key]+=1
            @test_throws ErrorException STUDY.check_result_rules(bad, entry, p)
        end
    end
end

@testset "F13 child-process wall watchdog preserves failure and does not overwrite" begin
    mktempdir() do dir
        script=joinpath(dir, "child.jl")
        write(
            script,
            "println(\"child_started\"); flush(stdout); sleep(parse(Float64, only(ARGS)))\n",
        )
        fast=joinpath(dir, "normal.log")
        cmd=`$(Base.julia_cmd()) --startup-file=no --threads=1 $script 0`
        r=BATCH.watch(cmd, fast; budget_sec = 30)
        @test r.process_success &&
              r.exit_code==0 &&
              r.term_signal==0 &&
              !r.timed_out &&
              r.process_budget_pass
        @test occursin("child_started", read(fast, String))
        @test_throws ErrorException BATCH.watch(cmd, fast; budget_sec = 30)
        slow=joinpath(dir, "timeout.log")
        cmd=`$(Base.julia_cmd()) --startup-file=no --threads=1 $script 30`
        r=BATCH.watch(cmd, slow; budget_sec = 2)
        @test r.timed_out &&
              !r.process_budget_pass &&
              !r.process_success &&
              (r.exit_code!=0 || r.term_signal!=0)
        @test isfile(slow) && r.process_elapsed_sec<15
        @test_throws ErrorException BATCH.watch(cmd, joinpath(dir, "invalid.log"); budget_sec = NaN)
    end
end
end
