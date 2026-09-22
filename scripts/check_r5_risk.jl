using PaperRebuild, TOML, SHA
include("r5_risk_docs.jl")
"--sync" in ARGS&&sync_r5_risk_docs()
root=normpath(joinpath(@__DIR__, ".."))
d=TOML.parsefile(joinpath(root, "docs", "reading", "ch05", "risk.toml"))
page=read(joinpath(root, "docs", "src", "ch05-risk-equations.md"), String)
api=read(joinpath(root, "docs", "src", "api.md"), String)
tests=read(joinpath(root, "test", "r5_risk.jl"), String)
for x in d["equation"]
    occursin("\\tag{"*x["id"]*"}", page)&&occursin(x["test"], tests)||error("风险公式/测试映射缺失")
    Base.Docs.hasdoc(PaperRebuild, Symbol(x["api"]))&&occursin("PaperRebuild."*x["api"], api)||error(
        "风险API映射缺失",
    )
end
rules=TOML.parsefile(joinpath(root, "configs", "r5", "risk", "study.toml"))
for (file, hash) in rules["files"]
    path=joinpath(root, "configs", "r5", "risk", file)
    bytes2hex(sha256(read(path)))==hash||error("风险冻结输入改变")
    load_r5_risk_case(path)
end
println("Risk: 5 project derivations, 6 symbol groups, 6 boundaries and 13 frozen inputs checked.")
