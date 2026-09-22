using PaperRebuild, TOML
include("r4_heat_docs.jl")
"--sync" in ARGS && sync_r4_heat_docs()
root=normpath(joinpath(@__DIR__, ".."))
d=TOML.parsefile(joinpath(root, "docs", "reading", "ch04", "heat-compatibility.toml"))
page=read(joinpath(root, "docs", "src", "ch04-heat-equations.md"), String)
api=read(joinpath(root, "docs", "src", "api.md"), String)
tests=read(joinpath(root, "test", "r4_heat_compatibility.jl"), String)
length(d["equation"])==5 && length(d["symbol"])==5 || error("HC映射数量错误")
for x in d["equation"]
    occursin("\\tag{"*x["id"]*"}", page) || error("公式页缺失")
    isdefined(PaperRebuild, Symbol(x["api"])) && occursin(x["api"], api) || error("API缺失")
    occursin(x["test"], tests) || error("测试映射缺失")
end
study=TOML.parsefile(joinpath(root, "configs", "r4", "heat-compatibility-study.toml"))
length(study["records"])==34 && length(study["bands"])==2 || error("冻结清单错误")
println("R4 heat: 5 equations / 5 symbol groups / 5 issues; 34 parents × 2 bands frozen.")
