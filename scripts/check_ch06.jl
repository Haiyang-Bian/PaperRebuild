include("ch06_docs.jl")
root = normpath(joinpath(@__DIR__, ".."))
ARGS in (String[], ["--sync"]) || error("usage: check_ch06.jl [--sync]")
"--sync" in ARGS && sync_ch06_docs()
d = TOML.parsefile(joinpath(root, "docs/reading/ch06/audit.toml"))
d["status"] == "selected_relations_audited_dispatch_not_implemented" || error("覆盖声明改变")
length(d["source_sha256"]) == 64 || error("缺原件身份")
for group in ["equation", "finding", "symbol"]
    ids = [x["id"] for x in d[group]]
    length(unique(ids)) == length(ids) || error("重复ID")
end
tests = read(joinpath(root, "test/ch06_audit.jl"), String)
for e in d["equation"]
    !isempty(e["source_equations"]) && occursin(e["test"], tests) || error("式-测试缺少映射")
end
all(startswith(s["julia"], "planned: ") for s in d["symbol"]) || error("不能把计划命名当实现")
read(joinpath(root, "docs/src/ch06-audit-equations.md"), String) == ch06_audit_markdown(root) ||
    error("生成式/符号页失步，请显式--sync")
println(
    "R7: selected 9 derivations, 12 findings and 9 planned symbol groups checked; no model API claim.",
)
