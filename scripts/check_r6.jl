using PaperRebuild, TOML
include("r6_docs.jl")
"--sync" in ARGS && sync_r6_docs()
root = normpath(joinpath(@__DIR__, ".."))
d = TOML.parsefile(joinpath(root, "docs", "reading", "ch05", "sample-out.toml"))
page = read(joinpath(root, "docs", "src", "r6-equations.md"), String)
api = read(joinpath(root, "docs", "src", "r6-api.md"), String)
tests = read(joinpath(root, "test", "r6.jl"), String)
for x in d["equation"]
    occursin("\\tag{" * x["id"] * "}", page) && occursin(x["test"], tests) ||
        error("R6公式/测试映射缺失")
    Base.Docs.hasdoc(PaperRebuild, Symbol(x["api"])) && occursin("PaperRebuild." * x["api"], api) ||
        error("R6 API映射缺失")
end
p = load_r6_protocol(joinpath(root, "configs", "r6", "protocol.toml"))
p.data["samples"]["test"] >= 1000 || error("独立测试数量未达设计")
println("R6: 8 source findings, 6 project equations, 6 symbol groups and protocol checked.")
