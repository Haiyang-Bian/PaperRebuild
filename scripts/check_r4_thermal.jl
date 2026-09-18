using PaperRebuild, TOML
include("r4_thermal_docs.jl")
"--sync" in ARGS && sync_r4_thermal_docs()
root=normpath(joinpath(@__DIR__, ".."))
d=TOML.parsefile(joinpath(root, "docs", "reading", "ch04", "thermal.toml"))
page=read(joinpath(root, "docs", "src", "ch04-thermal-equations.md"), String)
api=read(joinpath(root, "docs", "src", "api.md"), String)
tests=read(joinpath(root, "test", "r4_thermal.jl"), String)
length(d["equation"])==6 && length(d["symbol"])==5 && length(d["issue"])==5 ||
    error("热模型台账缺项")
for x in d["equation"]
    occursin("\\tag{"*x["id"]*"}", page) || error("缺少公式")
    isdefined(PaperRebuild, Symbol(x["api"])) && occursin("PaperRebuild."*x["api"], api) ||
        error("API链接缺失")
    occursin(x["test"], tests) || error("测试映射缺失")
end
println("R4 thermal: 6 project equations, 5 symbol groups and 5 scope decisions.")
