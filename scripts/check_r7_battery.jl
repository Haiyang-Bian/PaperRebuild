using PaperRebuild, TOML
include("r7_battery_docs.jl")
ARGS in (String[], ["--sync"]) || error("usage: check_r7_battery.jl [--sync]")
root=normpath(joinpath(@__DIR__, ".."))
page=joinpath(root, "docs/src/ch06-battery-equations.md")
"--sync" in ARGS && write(page, r7_battery_markdown(root))
data=TOML.parsefile(joinpath(root, "docs/reading/ch06/battery-domain.toml"))
for group in ("original_equation", "equation", "symbol")
    ids=[row["id"] for row in data[group]]
    length(ids)==length(unique(ids)) || error("电池台账ID重复")
end
tests=read(joinpath(root, "test/r7_battery.jl"), String)
for row in data["equation"]
    isdefined(PaperRebuild, Symbol(row["api"])) && occursin(row["test"], tests) ||
        error("电池API/测试映射错误")
end
read(page, String)==r7_battery_markdown(root) || error("电池生成页失步")
println("Battery source/interpretation records, 3 derivations and 3 symbol groups checked.")
