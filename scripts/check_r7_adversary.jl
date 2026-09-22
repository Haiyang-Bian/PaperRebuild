using PaperRebuild, JuMP, SHA
include("r7_adversary_docs.jl")
ARGS in (String[], ["--sync"]) || error("usage: check_r7_adversary.jl [--sync]")
root=normpath(joinpath(@__DIR__, ".."))
"--sync" in ARGS && sync_r7_adversary_docs(root)
d=TOML.parsefile(joinpath(root, "docs/reading/ch06/inner-adversary.toml"))
for kind in ("original_equation", "equation", "finding", "symbol")
    ids=[e["id"] for e in d[kind]]
    length(unique(ids))==length(ids) || error("内层台账ID重复")
end
tests=read(joinpath(root, "test/r7_adversary.jl"), String)
for e in d["equation"]
    isdefined(PaperRebuild, Symbol(e["api"])) && occursin(e["test"], tests) ||
        error("内层API/测试映射失配")
end
freeze=TOML.parsefile(joinpath(root, "configs/r7/inner-freeze.toml"))
for (p, h) in freeze["files"]
    bytes2hex(sha256(read(joinpath(root, p))))==h || error("三节点输入已改变")
end
c=load_r7_recovery_case(joinpath(root, "configs/r7/inner-tie-two-hour.toml"))
lp=r7_recovery_lp(c, [0, 1, 1])
validate_r7_dual(lp, [1, 0, 0], lp.data["dual_seed"])["dual_feasible"] || error("共同对偶证书错误")
read(joinpath(root, "docs/src/ch06-adversary-equations.md"), String)==r7_adversary_markdown(root) ||
    error("内层生成页失步")
println(
    "R7 inner: 7 original formulas, 5 derivations, 3 findings, 4 symbol groups, 3 frozen cases.",
)
