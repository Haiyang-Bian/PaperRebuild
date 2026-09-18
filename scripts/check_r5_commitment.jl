using PaperRebuild, TOML, SHA
include("r5_commitment_docs.jl")
"--sync" in ARGS&&sync_r5_commitment_docs()
root=normpath(joinpath(@__DIR__, ".."))
d=TOML.parsefile(joinpath(root, "docs", "reading", "ch05", "commitment.toml"))
page=read(joinpath(root, "docs", "src", "ch05-commitment-equations.md"), String)
api=read(joinpath(root, "docs", "src", "api.md"), String)
tests=read(joinpath(root, "test", "r5_commitment.jl"), String)
for x in d["equation"]
    occursin("\\tag{"*x["id"]*"}", page)&&occursin(x["test"], tests)||error("共同承诺公式/测试缺失")
    Base.Docs.hasdoc(PaperRebuild, Symbol(x["api"]))&&occursin("PaperRebuild."*x["api"], api)||error(
        "共同承诺API缺失",
    )
end
rules=TOML.parsefile(joinpath(root, "configs", "r5", "commitment", "study.toml"))
for (file, hash) in rules["files"]
    path=joinpath(root, "configs", "r5", "commitment", file)
    bytes2hex(sha256(read(path)))==hash||error("共同承诺冻结输入变化：$file")
    load_r5_commitment_case(path)
end
println(
    "Shared commitment: 5 project equations, 5 symbol groups, 6 boundaries and 10 frozen inputs checked.",
)
