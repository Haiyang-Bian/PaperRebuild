using PaperRebuild, TOML, SHA
include("r5_market_payment_docs.jl")
root=normpath(joinpath(@__DIR__, ".."))
ledger=TOML.parsefile(joinpath(root, "docs", "reading", "ch05", "strategic-model.toml"))
generated=replace(
    r5_market_payment_doc_text(ledger),
    "# 策略报价准备：支付推导与符号"=>"# 连续策略报价：公式与符号",
    "由strategic.toml生成。R5-SP是项目编号，连续策略报价优化尚未实现。" => "由strategic-model.toml生成。R5-ST为项目编号，明确区分原式与乐观选择等新增假设。",
)
path=joinpath(root, "docs", "src", "ch05-strategic-model-equations.md")
"--sync" in ARGS && (!isfile(path)||read(path, String)!=generated) && write(path, generated)
read(path, String)==generated || error("策略生成页不同步")
api=read(joinpath(root, "docs", "src", "api.md"), String)
testtext=join(
    read(joinpath(root, "test", f), String) for f in ("r5_strategic.jl", "r5_market_selection.jl")
)
for e in ledger["equation"]
    Base.Docs.hasdoc(PaperRebuild, Symbol(e["api"])) &&
    occursin("PaperRebuild."*e["api"], api) &&
    occursin(e["test"], testtext) || error("策略API/测试映射缺失")
end
source=joinpath(root, split(ledger["source"], '/')...)
isfile(source) &&
    bytes2hex(sha256(read(source)))!=ledger["source_sha256"] &&
    error("策略原件版本变化")
rules_path=joinpath(root, "configs", "r5", "strategic", "study.toml")
if isfile(rules_path)
    rules=TOML.parsefile(rules_path)
    for (file, hash) in rules["files"]
        p=joinpath(dirname(rules_path), file)
        bytes2hex(sha256(read(p)))==hash || error("冻结策略输入变化")
        load_r5_strategic_case(p)
    end
    bytes2hex(sha256(read(joinpath(@__DIR__, "r5_strategic_cases.jl")))) ==
    rules["fixture_sha256"] || error("冻结构造规则变化")
end
println("Strategic: 5 derivations, 5 symbol groups and 4 model boundaries checked.")
