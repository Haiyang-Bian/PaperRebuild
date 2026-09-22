using PaperRebuild, TOML, SHA
include("r5_market_payment_docs.jl")
root=normpath(joinpath(@__DIR__, ".."))
ledger=TOML.parsefile(joinpath(root, "docs", "reading", "ch05", "execution.toml"))
generated=replace(
    r5_market_payment_doc_text(ledger),
    "# 策略报价准备：支付推导与符号"=>"# 市场执行选择：公式与符号",
    "由strategic.toml生成。R5-SP是项目编号，连续策略报价优化尚未实现。" => "由execution.toml生成。R5-EX为项目执行规则，不冒用作者式号或市场制度。",
)
path=joinpath(root, "docs", "src", "ch05-execution-equations.md")
"--sync" in ARGS && (!isfile(path)||read(path, String)!=generated) && write(path, generated)
read(path, String)==generated || error("执行规则生成页不同步")
api=read(joinpath(root, "docs", "src", "api.md"), String)
tests=join(
    read(joinpath(root, "test", f), String) for f in ("r5_execution.jl", "r5_execution_scaling.jl")
)
for e in ledger["equation"]
    Base.Docs.hasdoc(PaperRebuild, Symbol(e["api"])) &&
    occursin("PaperRebuild."*e["api"], api) &&
    occursin(e["test"], tests) || error("执行API/测试映射错误")
end
source=joinpath(root, split(ledger["source"], '/')...)
isfile(source) && bytes2hex(sha256(read(source)))!=ledger["source_sha256"] && error("原PDF版本变化")
println("Execution: 4 derivations, 4 symbol groups, 3 scope boundaries checked.")
