using PaperRebuild, SHA
include("r7_thermal_docs.jl")
ARGS in (String[], ["--sync"]) || error("usage: check_r7_thermal.jl [--sync]")
root=normpath(joinpath(@__DIR__, ".."))
page=joinpath(root, "docs/src/ch06-thermal-equations.md")
"--sync" in ARGS && write(page, r7_thermal_markdown(root))
d=TOML.parsefile(joinpath(root, "docs/reading/ch06/thermal-reconstruction.toml"))
tests=read(joinpath(root, "test/r7_thermal.jl"), String)
for kind in ("equation", "finding", "symbol")
    ids=[x["id"] for x in d[kind]]
    length(ids)==length(unique(ids)) || error("热重构台账ID重复")
end
for x in d["equation"]
    isdefined(PaperRebuild, Symbol(x["api"])) && occursin(x["test"], tests) ||
        error("热重构API/测试映射错误")
end
freeze=TOML.parsefile(joinpath(root, "configs/r7/thermal-freeze.toml"))
for (name, v) in freeze["cases"]
    path=joinpath(root, "configs/r7/$name.toml")
    bytes2hex(sha256(read(path)))==v["file_sha256"] &&
    load_r7_recovery_case(path).sha256==v["case_sha256"] || error("热案例哈希失配")
end
read(page, String)==r7_thermal_markdown(root) || error("热重构生成页失步")
println(
    "R7 thermal: 5 project equations, 2 findings, 4 symbol groups, 2 pre-frozen analytic cases.",
)
