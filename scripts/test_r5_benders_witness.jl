include("r5_benders_report_tables.jl")
using Test
root=normpath(joinpath(@__DIR__, ".."))
public=joinpath(root, "results", "summaries", "r5-benders", "witnesses", "hard_zero--cuts--highs")
path=isempty(ARGS) ? public : only(ARGS)
ispublic=isfile(joinpath(path, "witness.toml"))
println("Reading saved fixture without optimization...");
flush(stdout)
loaded=ispublic ? r5_benders_read_witness(path) : read_r5_benders_run(path)
rules=TOML.parsefile(joinpath(root, "configs", "r5", "benders", "study.toml"))
file=only([file for (file, ref) in rules["references"] if ref["case_sha256"]==loaded.case.sha256])
reference=TOML.parsefile(joinpath(root, split(rules["references"][file]["witness"], '/')...))
entry=Dict(
    "id"=>"saved-fixture",
    "case"=>file,
    "route"=>loaded.result["spec"]["feasibility"],
    "solver"=>"highs",
)
@testset "公开分解见证独立重读与篡改" begin
    mktempdir() do dir
        target=joinpath(dir, "public")
        parent=ispublic ? loaded.parent_result_sha256 :
               bytes2hex(sha256(read(joinpath(path, "result.toml"))))
        println("Writing partitioned raw witness...")
        flush(stdout)
        r5_benders_write_witness(loaded.case, loaded.result, target, parent)
        println("Replaying partitioned witness...")
        flush(stdout)
        reread=r5_benders_read_witness(target)
        @test reread.parent_result_sha256==parent
        @test r5_benders_raw_hash(reread.result)==r5_benders_raw_hash(loaded.result)
        @test r5_benders_evidence_hash(reread.result["validation"])==bytes2hex(
            sha256(PaperRebuild.r5_risk_validation_text(loaded.result["validation"])),
        )
        @test reread.result["validation"]["model_pass"]
        println("Checking tables and tamper rejection...")
        flush(stdout)
        tables=r5_benders_report_tables(reread.case, reread.result, entry, reference)
        @test only(tables["comparison.csv"]).A2_pass
        @test all(x.pass for x in tables["selected-residuals.csv"])
        @test count(x->x.kind=="cost", tables["subproblems.csv"])==sum(
            length(s["cost_source_ids"]) for s in loaded.result["iterations"]
        )
        @test all(
            filesize(joinpath(base, f))<5*1024^2 for (base, _, files) in walkdir(target) for
            f in files
        )
        @test_throws ErrorException r5_benders_write_witness(
            loaded.case,
            loaded.result,
            target,
            parent,
        )
        f=first(readdir(joinpath(target, "subproblems"); join = true))
        original=read(f, String)
        s=TOML.parse(original)
        s["solver_objective"]=123456.0
        write(f, PaperRebuild.r5_market_text(s))
        @test_throws ErrorException r5_benders_read_witness(target)
        write(f, original)
        manifest=joinpath(target, "witness.toml")
        w=TOML.parsefile(manifest)
        w["result"]["cost_optimization_complete"]=false
        write(manifest, PaperRebuild.r5_market_text(w))
        @test_throws ErrorException r5_benders_read_witness(target)
    end
end
