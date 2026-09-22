using TOML, CSV, SHA
length(ARGS)==1||error(
    "参数：已有分解study.toml；此入口只汇总保存标量，完整重验使用check_r5_benders_artifacts.jl",
)
study_path=abspath(only(ARGS));
study=TOML.parsefile(study_path)
root=normpath(joinpath(@__DIR__, ".."))
refs=collect(CSV.File(joinpath(root, "results", "summaries", "r5-risk", "comparison.csv")))
println("Stored scalar audit; no optimization, no replacement for independent artifact replay.")
for e in study["records"]
    path=joinpath(dirname(study_path), e["id"], "result.toml")
    bytes2hex(sha256(read(path)))==e["result_sha256"]||error("保存原值变化")
    r=TOML.parsefile(path)
    v=r["validation"]
    ref=only(filter(x->x.case==e["case"]&&x.solver=="highs", refs))
    println(
        e["id"],
        " | ",
        r["status"],
        " | UB=",
        v["upper_bound"],
        " | ref=",
        ref.objective,
        " | n=",
        length(r["iterations"]),
        " | gap=",
        v["gap"]["relative"],
    )
    if r["status"]=="untrusted_or_unresolved_subproblem"
        for failure in get(r, "failure_sources", [])
            s=r["subproblems"][failure["source_id"]]
            sv=s["validation"]
            failed=filter(a->!a["pass"], get(sv, "rows", []))
            sort!(failed; by = a->-a["normalized"])
            println(
                "  scenario=",
                s["scenario"],
                " elastic=",
                s["elastic"],
                " status=",
                s["status"],
                " validation=",
                sv["status"],
                " failed rows=",
                length(failed),
            )
            for a in Iterators.take(failed, 3)
                println(
                    "    ",
                    a["kind"],
                    " ",
                    a["id"],
                    " residual=",
                    a["residual"],
                    " tolerance=",
                    a["tolerance"],
                    " normalized=",
                    a["normalized"],
                )
            end
        end
    end
end
