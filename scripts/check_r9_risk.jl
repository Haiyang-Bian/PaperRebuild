using PaperRebuild, TOML
include("r9_risk_docs.jl")
ARGS in (String[], ["--sync"]) || error("usage: check_r9_risk.jl [--sync]")
root=dirname(@__DIR__)
x=TOML.parsefile(joinpath(root, "docs/reading/ch07/risk-study.toml"))
!x["author_input_equivalence"] &&
!x["continuous_call_guarantee"] &&
!x["out_of_sample_completed"] || error("当前验收范围被改变")
page=read(joinpath(root, x["page"]), String)
Set(q["id"] for q in x["equations"])==Set("R9-RK$i" for i in 1:4) || error("公式漏项")
for q in x["equations"]
    isdefined(PaperRebuild, Symbol(q["api"])) && occursin("\\tag{"*q["id"]*"}", page) ||
        error("公式/API缺失")
end
allunique(q["id"] for q in x["symbols"]) || error("符号重复")
for a in get(x, "audit_equations", [])
    occursin("\\tag{"*a["id"]*"}", read(joinpath(root, a["page"]), String)) || error("审计公式遗漏")
    isfile(joinpath(root, a["implementation"])) && isfile(joinpath(root, a["test"])) ||
        error("审计来源遗漏")
end
occursin("R9-RK", read(joinpath(root, x["test_file"]), String)) || error("测试映射缺失")
load_r9_reserve_study(joinpath(root, "configs/r9/reserve-study.toml"))
file=joinpath(root, "docs/src/ch07-risk-generated.md")
"--sync" in ARGS && write(file, r9_risk_markdown())
read(file, String)==r9_risk_markdown() || error("符号导航失步")
println("R9 risk protocol/formula/API mapping passed; not statistical acceptance.")
