using PaperRebuild, TOML
root=normpath(joinpath(@__DIR__, ".."))
d=TOML.parsefile(joinpath(root, "docs", "reading", "ch04", "discrete.toml"))
page=read(joinpath(root, "docs", "src", "ch04-discrete.md"), String)
api=read(joinpath(root, "docs", "src", "api.md"), String)
tests=read(joinpath(root, "test", "r4_discrete.jl"), String)
length(unique(x["id"] for x in d["equation"]))==3 || error("项目式清单错误")
for row in d["equation"]
    occursin("\\tag{"*row["id"]*"}", page) || error("项目式缺失")
    isdefined(PaperRebuild, Symbol(row["api"]))&&occursin(row["api"], api) || error("API缺失")
    occursin(row["test"], tests) || error("测试映射缺失")
end
isempty(ARGS) || println(read_r4_discrete_run(only(ARGS)).validation)
println("R4 discrete: 3 project equations, 3 symbols and API/test mapping checked.")
