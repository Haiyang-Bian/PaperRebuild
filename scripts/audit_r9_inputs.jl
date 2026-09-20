# 原页转录审计，不优化、不下载；新目录拒绝覆盖。
include("r9_source_report.jl")
using .R9SourceReport
length(ARGS)==2 && ARGS[1] in ("write", "check") ||
    error("usage: audit_r9_inputs.jl write|check DIRECTORY")
out=abspath(ARGS[2])
audit=ARGS[1]=="write" ? R9SourceReport.write_report(out) : R9SourceReport.check_report(out)
println("R9 source audit: ", audit["electric"], "; ", audit["heat"])
println(
    "Arithmetic diagnostics: ",
    length(audit["rows"]),
    "; unresolved: ",
    count(r->r["status"]=="difference_requires_interpretation", audit["rows"]),
)
println("Original input complete: false; optimization performed: false")
