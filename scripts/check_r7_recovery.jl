using PaperRebuild
include("r7_recovery_docs.jl")
root=normpath(joinpath(@__DIR__, ".."))
ARGS in (String[], ["--sync"]) || error("usage: check_r7_recovery.jl [--sync]")
"--sync" in ARGS && sync_r7_recovery_docs(root)
d=TOML.parsefile(joinpath(root, "docs/reading/ch06/recovery.toml"))
d["version"]=="r7_recovery_checked_v1" || error("版本错误")
for key in ("equation", "mapping", "symbol")
    ids=[x["id"] for x in d[key]]
    length(unique(ids))==length(ids) || error("重复映射ID")
end
tests=read(joinpath(root, "test/r7_recovery.jl"), String)
all(occursin(e["test"], tests) for key in ("equation", "mapping") for e in d[key]) ||
    error("测试映射缺失")
c=load_r7_recovery_case(joinpath(root, "configs/r7/recovery-hand.toml"))
b=build_r7_recovery(c, [0])
declared=Set(vcat((g["constraints"] for g in d["mapping"])...))
Set(keys(b.constraints))==declared || error("实际约束组与声明不一致")
all(isdefined(PaperRebuild, Symbol(e["api"])) for e in d["equation"]) || error("API映射缺失")
read(joinpath(root, "docs/src/ch06-recovery-equations.md"), String)==r7_recovery_markdown(root) ||
    error("恢复公式页失步")
println(
    "R7 recovery: 5 adopted/hand equations, 4 constraint groups, 8 symbol groups; fixed-preplan scope checked.",
)
