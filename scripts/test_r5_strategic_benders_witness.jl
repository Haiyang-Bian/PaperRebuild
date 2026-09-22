include("r5_strategic_benders_report_tables.jl")
using Test
root = normpath(joinpath(@__DIR__, ".."))
path =
    isempty(ARGS) ?
    joinpath(
        root,
        "results",
        "summaries",
        "r5-strategic-benders",
        "witnesses",
        "competitive_hard_zero--cuts",
    ) : only(ARGS)
public = isfile(joinpath(path, "witness.toml"))
x = public ? r5_sb_read_witness(path) : read_r5_strategic_benders_run(path)
parent = public ? x.parent_result_sha256 : bytes2hex(sha256(read(joinpath(path, "result.toml"))))
@testset "策略分解公开原值独立重验" begin
    mktempdir() do dir
        target = joinpath(dir, "public")
        r5_sb_write_witness(x.case, x.result, target, parent)
        y = r5_sb_read_witness(target)
        @test y.case.sha256 == x.case.sha256
        @test y.parent_result_sha256 == parent
        @test r5_benders_raw_hash(y.result) == r5_benders_raw_hash(x.result)
        @test r5_benders_evidence_hash(y.result["validation"]) ==
              r5_benders_evidence_hash(x.result["validation"])
        @test all(
            filesize(joinpath(base, f)) < 5*1024^2 for (base, _, fs) in walkdir(target) for f in fs
        )
        @test_throws ErrorException r5_sb_write_witness(x.case, x.result, target, parent)
        manifest = joinpath(target, "witness.toml")
        original = read(manifest, String)
        for change in (
            w->(
                w["result"]["cost_optimization_complete"] =
                    !w["result"]["cost_optimization_complete"]
            ),
            w->(w["result"]["selection"] = "min_norm"),
            w->(w["raw_result_content_sha256"] = "changed"),
            w->(w["validation_sha256"]["result"] = "changed"),
        )
            w = TOML.parse(original)
            change(w)
            write(manifest, PaperRebuild.r5_market_text(w))
            @test_throws ErrorException r5_sb_read_witness(target)
            write(manifest, original)
        end
        f = first(readdir(joinpath(target, "iterations"); join = true))
        raw = read(f, String)
        write(f, raw*"\n# tamper\n")
        @test_throws ErrorException r5_sb_read_witness(target)
        write(f, raw)
        write(joinpath(target, "extra.toml"), "extra = true\n")
        @test_throws ErrorException r5_sb_read_witness(target)
    end
end
