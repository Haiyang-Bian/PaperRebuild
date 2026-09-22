using Test
include("report_r6_study.jl")
length(ARGS)==2 || error("usage: test_r6_study_report_artifacts.jl <raw-batch> <verified-report>")
source, report=ARGS

function reseal_metadata(dir, meta)
    write(joinpath(dir, "report.toml"), r6_study_text(meta))
    write(joinpath(dir, "report.sha256"), r6_study_hash(joinpath(dir, "report.toml"))*"\n")
end

@testset "R6 report saved numeric replay and tamper rejection" begin
    @test check_r6_study_report(source, report)===nothing
    @test_throws ErrorException report_r6_study(source, report; partial = true)
    @test_throws ErrorException r6_report_path(source, "../outside")
    @test_throws ErrorException r6_report_path(source, "C:/outside")
    @test_throws ErrorException r6_report_path(source, "a\\outside")
    mktempdir() do tmp
        altered=joinpath(tmp, "altered")
        cp(report, altered)
        meta=TOML.parsefile(joinpath(altered, "report.toml"))
        file="training.csv"
        original=read(joinpath(altered, file), String)
        write(joinpath(altered, file), replace(original, "solver_optimal"=>"invented_success"))
        @test read(joinpath(altered, file), String)!=original
        meta["tables"][file]=r6_study_hash(joinpath(altered, file))
        reseal_metadata(altered, meta)
        # 即使篡改者重算自身文件哈希，仍须被原值回代拒绝。
        @test_throws ErrorException check_r6_study_report(source, altered)
        narrowed=joinpath(tmp, "narrowed")
        cp(report, narrowed)
        meta=TOML.parsefile(joinpath(narrowed, "report.toml"))
        meta["origin"]="thesis_verified"
        reseal_metadata(narrowed, meta)
        @test_throws ErrorException check_r6_study_report(source, narrowed)
    end
end
