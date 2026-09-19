include("r5_market_payment_docs.jl")
function r5_strategic_benders_doc_text()
    root = normpath(joinpath(@__DIR__, ".."))
    ledger = TOML.parsefile(joinpath(root, "docs", "reading", "ch05", "strategic-benders.toml"))
    replace(
        r5_market_payment_doc_text(ledger),
        "# 策略报价准备：支付推导与符号"=>"# 策略报价分解：公式与符号",
        "由strategic.toml生成。R5-SP是项目编号，连续策略报价优化尚未实现。" => "由strategic-benders.toml生成。R5-SB为项目采用推导，市场/舒适分支的作用域分别登记。",
    )
end
function sync_r5_strategic_benders_docs()
    path = joinpath(@__DIR__, "..", "docs", "src", "ch05-strategic-benders-equations.md")
    text = r5_strategic_benders_doc_text()
    (!isfile(path) || read(path, String) != text) && write(path, text)
end
