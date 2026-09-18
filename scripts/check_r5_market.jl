using PaperRebuild, TOML
include("r5_market_docs.jl")
"--sync" in ARGS && sync_r5_market_docs()
root=normpath(joinpath(@__DIR__, ".."))
ledger=TOML.parsefile(joinpath(root, "docs", "reading", "ch05", "market.toml"))
page=read(joinpath(root, "docs", "src", "ch05-market-equations.md"), String)
api=read(joinpath(root, "docs", "src", "api.md"), String)
tests=read(joinpath(root, "test", "r5_market.jl"), String)
length(ledger["equation"])==9 && length(ledger["symbol"])==17 && length(ledger["issue"])==5 ||
    error("市场台账范围变化，须显式审阅")
for category in ("equation", "symbol", "issue")
    ids=[x["id"] for x in ledger[category]]
    length(unique(ids))==length(ids) || error("重复稳定ID")
end
for x in ledger["equation"]
    occursin("\\tag{"*x["id"]*"}", page) || error("原式展示缺失")
    isdefined(PaperRebuild, Symbol(x["api"])) && occursin("PaperRebuild."*x["api"], api) ||
        error("API卡片缺失")
    Base.Docs.hasdoc(PaperRebuild, Symbol(x["api"])) || error("API缺docstring")
    occursin(x["test"], tests) || error("测试关联缺失")
end
for x in ledger["symbol"],
    key in ("latex", "meaning", "category", "unit", "julia", "dimensions", "domain", "source")

    !isempty(strip(x[key])) || error("符号字段缺失：$key")
end
println(
    "R5 fixed-bid market: 9 original equations, 17 symbol groups and 5 adoption boundaries mapped.",
)
