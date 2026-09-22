using PaperRebuild, TOML
include("r9_reserve_docs.jl")
ARGS in (String[], ["--sync"]) || error("usage: check_r9_reserve.jl [--sync]")
root=dirname(@__DIR__)
x=TOML.parsefile(joinpath(root, "docs/reading/ch07/reserve.toml"))
x["schema"]=="r9-reserve-adoption-v1" &&
!x["original_input_reproduction"] &&
!x["full_electric_physics_certified"] &&
!x["formal_risk_experiment_completed"] || error("本节点的研究范围声明发生变化")
page=read(joinpath(root, x["page"]), String)
tests=read(joinpath(root, x["test_file"]), String)
all(t->occursin(t, tests), x["tests"]) || error("测试映射缺失")
Set(q["id"] for q in x["equations"])==Set("R9-RS$i" for i in 1:4) || error("编号映射不完整")
for q in x["equations"]
    isdefined(PaperRebuild, Symbol(q["api"])) && occursin("\\tag{"*q["id"]*"}", page) ||
        error("公式或API缺失")
end
allunique(s["id"] for s in x["symbols"]) || error("符号重复")
c=r9_reserve_template(joinpath(root, "docs/reading/ch07"), joinpath(root, x["protocol"]))
audit_r9_reserve_input(c)["reference_pass"] || error("预运行参考未通过")
target=joinpath(root, "docs/src/ch07-reserve-generated.md")
"--sync" in ARGS && write(target, r9_reserve_markdown())
read(target, String)==r9_reserve_markdown() || error("符号索引失步")
println("R9 reserve input/formula/API mapping passed; no risk optimization performed.")
