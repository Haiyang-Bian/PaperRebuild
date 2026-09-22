using TOML, Test, PaperRebuild
VERSION==v"1.12.6" || error("Use Julia 1.12.6")
ARGS in (String[], ["--sync"]) || error("Usage: check_r9_scalability.jl [--sync]")
root=dirname(@__DIR__)
x=TOML.parsefile(joinpath(root, "docs/reading/ch04/scalability.toml"))
page=read(joinpath(root, x["page"]), String)
tests=read(joinpath(root, x["test"]), String)
io=IOBuffer()
println(
    io,
    "# 主体拆分符号表\n\n<!-- generated from docs/reading/ch04/scalability.toml; do not edit -->\n",
)
println(io, "以下为项目推导符号，不能冒称论文原有扩容规则。\n")
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
text=String(take!(io))
target=joinpath(root, x["generated"])
ARGS==["--sync"] && write(target, text)
@testset "R9-SC source, formulas, symbols and native APIs" begin
    @test !x["original_input_complete"] && !x["formal_scalability_experiments_complete"]
    @test [r["aggregators"] for r in x["author_table_4_9"]]==[6, 15, 30]
    @test length(unique(s["id"] for s in x["symbol"]))==length(x["symbol"])
    @test all(s->all(k->!isempty(s[k]), ("meaning", "unit", "julia")), x["symbol"])
    for f in x["formula"]
        @test occursin("\\tag{"*f["id"]*"}", page) && occursin(f["id"], tests)
        for api in f["api"]
            @test isdefined(PaperRebuild, Symbol(api)) && occursin(api, page)
        end
    end
    @test read(target, String)==text
end
