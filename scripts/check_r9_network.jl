using PaperRebuild, TOML
include("r9_network_docs.jl")
ARGS in (String[], ["--sync"]) || error("usage: check_r9_network.jl [--sync]")
root=dirname(@__DIR__)
x=TOML.parsefile(joinpath(root, "docs/reading/ch07/network.toml"))
x["schema"]=="r9-network-adoption-v1" &&
!x["original_input_reproduction"] &&
!x["full_thermal_physics_certified"] || error("模型范围漂移")
page=read(joinpath(root, x["page"]), String)
tests=read(joinpath(root, x["test_file"]), String)
all(t->occursin(t, tests), x["tests"]) || error("测试映射缺失")
Set(q["id"] for q in x["equations"])==Set("R9-RN$i" for i in 1:5) || error("方程映射不完整")
for q in x["equations"]
    isdefined(PaperRebuild, Symbol(q["api"])) || error("API缺失")
    occursin("\\tag{"*q["id"]*"}", page) || error("编号公式缺失")
end
for api in x["new_apis"]
    isdefined(PaperRebuild, Symbol(api)) && occursin(api, page) || error("新API卡片缺失")
end
allunique(s["id"] for s in x["symbols"]) || error("符号ID重复")
p=TOML.parsefile(joinpath(root, x["protocol"]))
p["source_sha256"]==x["source_sha256"] || error("来源不符")
parent=r9_trading_case(
    joinpath(root, "docs/reading/ch07"),
    joinpath(root, "configs/r9/trading-protocol.toml"),
)
for design in (:legacy, :equipment), policy in (:fixed, :electric, :heat, :joint)
    r9_reconfiguration_case(parent, p; design, policy)
end
target=joinpath(root, "docs/src/ch07-network-generated.md")
"--sync" in ARGS && write(target, r9_network_markdown())
read(target, String)==r9_network_markdown() || error("符号/公式索引失步")
println("R9 network mapping and eight input policies passed; no optimization.")
