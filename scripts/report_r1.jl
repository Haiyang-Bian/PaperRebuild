using PaperRebuild
using TOML

length(ARGS) >= 1 || error("传入一个或多个运行目录")
for dir in ARGS
    saved = read_r1_run(dir)
    r = saved.result
    v = validate_r1_solution(saved.case, r)
    println(
        saved.metadata["run_id"],
        " status=",
        r["status"],
        " objective=",
        get(r, "objective", "none"),
    )
    println("relaxed=", v.relaxed_pass, " original_branch=", v.original_branch_pass)
    if !isempty(v.rows)
        println("max normalized residual=", maximum(x.residual / x.tolerance for x in v.rows))
        for row in v.rows
            row.pass || println(row)
        end
    end
end
