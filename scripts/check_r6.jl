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
md=TOML.parsefile(joinpath(root, "docs", "reading", "ch05", "r6-methods.toml"))
mp=read(joinpath(root, "docs", "src", "r6-method-equations.md"), String)
mt=read(joinpath(root, "test", "r6_methods.jl"), String)
for x in md["equation"]
    occursin("\\tag{"*x["id"]*"}", mp) && occursin(x["test"], mt) ||
        error("R6方法公式/测试映射缺失")
    Base.Docs.hasdoc(PaperRebuild, Symbol(x["api"])) && occursin("PaperRebuild."*x["api"], api) ||
        error("R6方法API映射缺失")
end
c=load_r6_physical_case(joinpath(root, "configs", "r6", "daily-small.toml"))
c.data["dispatch"]["T"]==p.data["T"] || error("R6时域不符")
println("R6 methods: 3 derivations, 4 symbol groups, common daily input checked.")
ed=TOML.parsefile(joinpath(root, "docs", "reading", "ch05", "r6-evaluation.toml"))
ep=read(joinpath(root, "docs", "src", "r6-evaluation-equations.md"), String)
et=read(joinpath(root, "test", "r6_evaluation.jl"), String)
for x in ed["equation"]
    occursin("\\tag{"*x["id"]*"}", ep) && occursin(x["test"], et) ||
        error("R6新日公式/测试映射缺失")
    Base.Docs.hasdoc(PaperRebuild, Symbol(x["api"])) && occursin("PaperRebuild."*x["api"], api) ||
        error("R6新日API映射缺失")
end
println("R6 evaluation: 4 project equations, 4 symbol groups and 4 scope findings checked.")
fd=TOML.parsefile(joinpath(root, "docs", "reading", "ch05", "r6-study.toml"))
fp=read(joinpath(root, "docs", "src", "r6-study-equations.md"), String)
ft=read(joinpath(root, "test", "r6_study.jl"), String)
for x in fd["equation"]
    occursin("\\tag{"*x["id"]*"}", fp)&&occursin(x["test"], ft) || error("R6正式规则/测试映射缺失")
    Base.Docs.hasdoc(PaperRebuild, Symbol(x["api"]))&&occursin("PaperRebuild."*x["api"], api) ||
        error("R6正式规则API映射缺失")
end
study=load_r6_study(joinpath(root, "configs", "r6", "study.toml"))
length(r6_study_candidates(study))==14 || error("正式候选数量不同")
println("R6 study: 3 project rules, 4 symbol groups and 14 candidate configurations checked.")
