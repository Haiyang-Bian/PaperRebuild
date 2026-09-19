using Test
include("r6_pilot_report.jl")

# 新进程从公开见证重新验算，再分别检查篡改和清单扩张会被拒绝。
# 临时副本由 mktempdir 管理，不修改已冻结报告或原始运行。
function test_r6_pilot_artifacts(dir)
    @testset "R6 pilot independent replay and integrity" begin
        @test isnothing(r6_check_pilot_report(dir))
        meta=TOML.parsefile(joinpath(dir, "pilot.toml"))
        @test length(meta["records"])==6
        @test !meta["full_build"]["optimized"]
        allrows=NamedTuple[]
        chunks=sort(filter(f->startswith(f, "residuals-"), readdir(dir)))
        for file in chunks
            append!(allrows, NamedTuple.(CSV.File(joinpath(dir, file))))
        end
        @test !isempty(allrows)
        @test all(row.pass for row in allrows)
        @test maximum(row.normalized for row in allrows)<=1.0
        println(
            "Independent residuals: ",
            length(allrows),
            "; max normalized = ",
            maximum(row.normalized for row in allrows),
        )
        mktempdir() do temp
            copy=joinpath(temp, "中文 公开副本")
            cp(dir, copy)
            file=joinpath(copy, "comparison.csv")
            original=read(file)
            open(file, "a") do io
                write(io, "altered\n")
            end
            @test_throws ErrorException r6_check_pilot_report(copy)
            write(file, original)
            extra=joinpath(copy, "undeclared.txt")
            write(extra, "not in frozen inventory")
            @test_throws ErrorException r6_check_pilot_report(copy)
        end
    end
end

if abspath(PROGRAM_FILE)==(@__FILE__)
    length(ARGS)<=1 || error("usage: test_r6_pilot_artifacts.jl [report]")
    dir=isempty(ARGS) ? joinpath(@__DIR__, "..", "results", "summaries", "r6-training-pilot-v1") :
        only(ARGS)
    test_r6_pilot_artifacts(dir)
end
