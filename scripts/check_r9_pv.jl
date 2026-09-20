using PaperRebuild, TOML
include("r9_pv_docs.jl")
root=normpath(joinpath(@__DIR__, ".."))
ledger=TOML.parsefile(joinpath(root, "docs/reading/ch07/pv-adoption.toml"))
ledger["schema"]=="r9-pv-adoption-v1" && !ledger["original_input_reproduction"] ||
    error("采用式身份错误")
Set(x["id"] for x in ledger["equations"])==Set("R9-P$i" for i in 1:6) || error("采用式缺失")
page=read(joinpath(root, "docs/src/ch07-pv.md"), String)
tests=read(joinpath(root, "test/r9_pv.jl"), String)
occursin(ledger["test"], tests) || error("缺少映射测试")
for row in ledger["equations"]
    isdefined(PaperRebuild, Symbol(row["api"])) || error("API缺失")
    occursin("\\tag{"*row["id"]*"}", page) || error("编号公式缺失")
end
numerics=TOML.parsefile(joinpath(root, "docs/reading/ch07/numerics.toml"))
numerics["schema"]=="r9-numerics-adoption-v1" && !numerics["original_input_reproduction"] ||
    error("数值解释身份错误")
Set(x["id"] for x in numerics["equations"])==Set("R9-N$i" for i in 1:6) || error("数值推导缺失")
npage=read(joinpath(root, "docs/src/ch07-numerics.md"), String)
for row in numerics["equations"]
    isdefined(PaperRebuild, Symbol(row["api"])) || error("数值API缺失")
    occursin("\\tag{"*row["id"]*"}", npage) || error("数值编号公式缺失")
end
isfile(joinpath(root, numerics["test_file"])) || error("数值测试缺失")
flow=TOML.parsefile(joinpath(root, "docs/reading/ch07/flow.toml"))
flow["schema"]=="r9-flow-adoption-v1" && !flow["original_input_reproduction"] ||
    error("变流量解释身份错误")
Set(x["id"] for x in flow["equations"])==Set("R9-V$i" for i in 1:5) || error("变流量推导缺失")
fpage=read(joinpath(root, "docs/src/ch07-flow.md"), String)
for row in flow["equations"]
    isdefined(PaperRebuild, Symbol(row["api"])) || error("变流量API缺失")
    occursin("\\tag{"*row["id"]*"}", fpage) || error("变流量编号公式缺失")
    if haskey(row, "test_file")
        occursin(row["test"], read(joinpath(root, row["test_file"]), String)) ||
            error("公式测试缺失")
    end
end
occursin(flow["test"], read(joinpath(root, flow["test_file"]), String)) ||
    error("变流量测试映射缺失")
for row in get(flow, "diagnostics", [])
    isfile(joinpath(root, row["implementation"])) || error("诊断实现缺失")
    occursin(row["test"], read(joinpath(root, row["test_file"]), String)) ||
        error("诊断测试映射缺失")
    occursin("\\tag{"*row["id"]*"}", fpage) || error("诊断编号公式缺失")
end
c=r9_pv_case(joinpath(root, "docs/reading/ch07"), joinpath(root, "configs/r9/pv-protocol.toml"))
audit_r9_pv_input(c).pass || error("输入核查未通过")
expected=r9_pv_markdown(root)
target=joinpath(root, "docs/src/ch07-pv-generated.md")
ARGS in (String[], ["--sync"]) || error("usage: check_r9_pv.jl [--sync]")
"--sync" in ARGS && write(target, expected)
read(target, String)==expected || error("符号索引失步")
println("R9 PV mapping/input checks passed; no optimization.")
