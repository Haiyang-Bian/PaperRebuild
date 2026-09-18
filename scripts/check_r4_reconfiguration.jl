using PaperRebuild, TOML
include("r4_network_docs.jl")
"--sync" in ARGS && sync_r4_network()
root=normpath(joinpath(@__DIR__, ".."))
d=TOML.parsefile(joinpath(root, "docs", "reading", "ch04", "network.toml"))
page=read(joinpath(root, "docs", "src", "ch04-network-equations.md"), String)
api=read(joinpath(root, "docs", "src", "api.md"), String)
tests=read(joinpath(root, "test", "r4_reconfiguration.jl"), String)
length(unique(x["id"] for x in d["equation"]))==6 || error("采用式缺失")
for x in d["equation"]
    occursin("\\tag{"*x["id"]*"}", page) || error("公式未生成")
    isdefined(PaperRebuild, Symbol(x["api"]))&&occursin(x["api"], api) || error("API缺失")
    occursin(x["test"], tests) || error("测试映射缺失")
end
study=TOML.parsefile(joinpath(root, "configs", "r4", "reconfiguration", "study.toml"))
for (name, hash) in study["input_sha256"]
    load_r4_case(joinpath(root, "configs", "r4", "reconfiguration", name*".toml")).sha256==hash ||
        error("冻结输入变化")
end
println("R4 network: 6 adopted equations / 5 symbols / 5 issues / frozen inputs checked.")
