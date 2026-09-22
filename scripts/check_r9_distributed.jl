using TOML, Test, PaperRebuild
VERSION==v"1.12.6" || error("Expected Julia 1.12.6")
ARGS in (String[], ["--sync"]) || error("usage: check_r9_distributed.jl [--sync]")
root=dirname(@__DIR__)
x=TOML.parsefile(joinpath(root, "docs/reading/ch07/distributed.toml"))
page=read(joinpath(root, x["page"]), String)
tests=read(joinpath(root, x["test"]), String)
io=IOBuffer()
println(
    io,
    "# 分布边界协调符号与采用式索引\n\n<!-- generated from docs/reading/ch07/distributed.toml; do not edit -->\n",
)
println(io, "定义以台账为准；原式出处沿用第4章核读，R9-DC编号为项目补充。\n")
println(io, "| 符号 | 含义 | 单位 | Julia字段 |\n| --- | --- | --- | --- |")
for s in x["symbol"]
    println(
        io,
        "| ``",
        s["latex"],
        "`` | ",
        s["meaning"],
        " | ",
        s["unit"],
        " | `",
        s["julia"],
        "` |",
    )
end
println(io, "\n## 采用式\n")
for f in x["formula"]
    println(io, "- **", f["id"], "**：", f["meaning"])
end
generated=String(take!(io))
path=joinpath(root, x["generated"])
ARGS==["--sync"] && write(path, generated)
@testset "R9 distributed formulas, symbols, API and original boundaries" begin
    @test isfile(joinpath(root, x["parent"])) &&
          x["origin"]=="synthetic" &&
          !x["original_input_complete"]
    @test length(unique(s["id"] for s in x["symbol"]))==length(x["symbol"])
    @test all(s->all(k->!isempty(s[k]), ("meaning", "unit", "julia")), x["symbol"])
    for f in x["formula"]
        @test occursin("\\tag{"*f["id"]*"}", page) && occursin(f["id"], tests)
        for api in f["api"]
            @test isdefined(PaperRebuild, Symbol(api)) && occursin(api, page)
        end
    end
    @test read(path, String)==generated
end
