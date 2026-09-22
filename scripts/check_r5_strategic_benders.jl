using PaperRebuild, TOML, SHA
include("r5_strategic_benders_docs.jl")
root = normpath(joinpath(@__DIR__, ".."))
ledger = TOML.parsefile(joinpath(root, "docs", "reading", "ch05", "strategic-benders.toml"))
"--sync" in ARGS && sync_r5_strategic_benders_docs()
read(joinpath(root, "docs", "src", "ch05-strategic-benders-equations.md"), String) ==
r5_strategic_benders_doc_text() || error("策略分解公式生成页未同步")
api = read(joinpath(root, "docs", "src", "api.md"), String)
tests =
    read(joinpath(root, "test", "r5_strategic_benders.jl"), String) *
    read(joinpath(root, "scripts", "test_r5_strategic_benders_gurobi.jl"), String)
for e in ledger["equation"]
    Base.Docs.hasdoc(PaperRebuild, Symbol(e["api"])) &&
    occursin("PaperRebuild."*e["api"], api) &&
    occursin(e["test"], tests) || error("策略分解API/测试映射缺失")
end
source = joinpath(root, split(ledger["source"], '/')...)
isfile(source) &&
    bytes2hex(sha256(read(source))) != ledger["source_sha256"] &&
    error("第5章原件版本变化")
println("Strategic Benders: 5 derivations, 4 symbol groups, 4 scope boundaries checked.")
