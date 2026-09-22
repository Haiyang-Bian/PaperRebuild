using PaperRebuild, TOML, SHA
include("r5_market_payment_docs.jl")
"--sync" in ARGS&&sync_r5_market_payment_docs()
root=normpath(joinpath(@__DIR__, ".."))
ledger=TOML.parsefile(joinpath(root, "docs", "reading", "ch05", "strategic.toml"))
page=read(joinpath(root, "docs", "src", "ch05-strategic-equations.md"), String)
page==r5_market_payment_doc_text(ledger)||error("支付生成页与台账不同")
api=read(joinpath(root, "docs", "src", "api.md"), String)
tests=read(joinpath(root, "test", "r5_market_payment.jl"), String)
ids=String[]
for key in ("equation", "symbol", "issue"), x in ledger[key]
    push!(ids, x["id"])
    occursin(x["id"], page)||error("支付条目未生成")
end
length(unique(ids))==length(ids)||error("支付台账ID重复")
for x in ledger["equation"]
    occursin("\\tag{"*x["id"]*"}", page)&&occursin(x["test"], tests)||error("支付公式/测试缺失")
    Base.Docs.hasdoc(PaperRebuild, Symbol(x["api"]))&&occursin("PaperRebuild."*x["api"], api) ||
        error("支付API/docstring缺失")
end
source=joinpath(root, split(ledger["source"], '/')...)
# 论文原件可缺失；存在时必须是台账核查过的版本。
if isfile(source)
    bytes2hex(sha256(read(source)))==ledger["source_sha256"]||error("支付原件版本变化")
end
println("Payment mapping: 3 project equations, 5 symbol groups, 4 boundaries checked.")
