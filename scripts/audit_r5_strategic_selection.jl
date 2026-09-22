include("r5_strategic_selection_audit.jl")
length(ARGS)==1||error("参数：策略公共报告目录")
dir=abspath(only(ARGS))
any(ispath(joinpath(dir, f)) for f in ("selection-audit.csv", "selection-audit.toml")) &&
    error("不覆盖选择审计")
rows=r5_strategic_selection_audit(dir)
CSV.write(joinpath(dir, "selection-audit.csv"), rows)
meta=Dict(
    "schema"=>"r5-strategic-selection-audit-v1",
    "solver_reexecuted"=>false,
    "script_sha256"=>bytes2hex(sha256(read(joinpath(@__DIR__, "r5_strategic_selection_audit.jl")))),
    "time_rows"=>length(rows),
    "different_award_rows"=>count(x->!x.same_awards_A1, rows),
    "scope"=>"Independent lower LP has the same optimal value; award differences do not change the declared optimistic validation and are not actual implementability certification.",
)
write(joinpath(dir, "selection-audit.toml"), PaperRebuild.r5_market_text(meta))
r5_strategic_check_selection_audit(dir)
println(
    "Selection audit: ",
    meta["different_award_rows"],
    "/",
    meta["time_rows"],
    " time rows use different independent awards.",
)
