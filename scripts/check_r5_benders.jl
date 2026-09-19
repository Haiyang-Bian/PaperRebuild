using PaperRebuild, TOML
include("r5_benders_docs.jl")
"--sync" in ARGS&&sync_r5_benders_docs()
root=normpath(joinpath(@__DIR__, ".."))
d=TOML.parsefile(joinpath(root, "docs", "reading", "ch05", "benders.toml"))
page=read(joinpath(root, "docs", "src", "ch05-benders-equations.md"), String)
api=read(joinpath(root, "docs", "src", "api.md"), String)
tests=join(
    read(joinpath(root, "test", file), String) for file in ("r5_benders.jl", "r5_benders_loop.jl")
)
for x in d["equation"]
    occursin("\\tag{"*x["id"]*"}", page)&&occursin(x["test"], tests)||error(
        "Benders公式/测试映射缺失",
    )
    Base.Docs.hasdoc(PaperRebuild, Symbol(x["api"]))&&occursin("PaperRebuild."*x["api"], api)||error(
        "Benders API映射缺失",
    )
end
for name in ("equation", "symbol", "issue")
    ids=[x["id"] for x in d[name]]
    length(ids)==length(unique(ids))||error("Benders台账ID重复")
end
println(
    "Benders: ",
    length(d["equation"]),
    " derivations, ",
    length(d["symbol"]),
    " symbol groups, ",
    length(d["issue"]),
    " boundaries checked; formal algorithm study pending.",
)
