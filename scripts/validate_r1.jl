using PaperRebuild

length(ARGS) == 1 || error("用法：julia --project=. scripts/validate_r1.jl <运行目录>")
saved = read_r1_run(ARGS[1])
report = validate_r1_solution(saved.case, saved.result)
println(
    "status=",
    report.status,
    " relaxed_pass=",
    report.relaxed_pass,
    " original_branch_pass=",
    report.original_branch_pass,
)
for row in report.rows
    row.pass || println(row)
end
report.relaxed_pass && report.original_branch_pass || error("独立验证未全部通过")
