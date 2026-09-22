# 默认只读：检查公式/API/测试映射。带报告目录可验收；--seal/--publish显式写入。
using TOML, SHA, CSV
root=normpath(joinpath(@__DIR__, ".."))
table=TOML.parsefile(joinpath(root, "docs", "reading", "ch04", "baseline-model.toml"))
doc=read(joinpath(root, "docs", "src", "ch04-baseline.md"), String)
api=read(joinpath(root, "docs", "src", "api.md"), String)
tests=read(joinpath(root, "test", "r4_baseline.jl"), String)
for e in table["equation"]
    occursin(e["id"], doc) || error("缺失方程说明")
    occursin(e["api"], api) || error("缺失API卡片")
    occursin(e["api"], read(joinpath(root, e["source"]), String)) || error("源码映射失效")
    occursin(e["test"], tests) || error("缺失测试映射")
end
println("R4 baseline: ", length(table["equation"]), " project equations/API/test mappings checked.")
positional=filter(x->!startswith(x, "--"), ARGS)
isempty(positional) && exit()
length(positional)==1 || error("提供一个报告目录")
dir=only(positional)
seal="--seal" in ARGS
publish="--publish" in ARGS
rows=collect(CSV.File(joinpath(dir, "comparison.csv")))
length(rows)==13 || error("证据数量不完整")
frozen=TOML.parsefile(joinpath(root, "configs", "r4", "baseline", "study.toml"))
inputs=Dict(e["name"]=>e["sha256"] for e in frozen["case"])
for r in rows
    r.input_sha256==inputs[r.case] || error("输入不匹配")
    isabspath(r.path) && error("绝对路径泄漏")
end
TOML.parsefile(joinpath(dir, "solver-comparison.toml"))["pass"] || error("A2未通过")
for (file, script) in (
    ("report.toml", "scripts/report_r4_baseline.jl"),
    ("figure-config.toml", "scripts/plot_r4_baseline.jl"),
)
    TOML.parsefile(joinpath(dir, file))["script_sha256"] ==
    bytes2hex(sha256(read(joinpath(root, script)))) || error("脚本与报告不匹配")
end
for (file, hash) in TOML.parsefile(joinpath(dir, "figure-config.toml"))["source_sha256"]
    bytes2hex(sha256(read(joinpath(dir, file))))==hash || error("图源哈希不匹配")
end
hashes=Dict{String,String}()
for (folder, _, files) in walkdir(dir), file in files
    file=="artifact-hashes.toml" && continue
    path=joinpath(folder, file)
    stat(path).size<=5*1024^2 || error("摘要单文件超过限制")
    if endswith(file, ".csv") || endswith(file, ".toml")
        occursin(r"(?i)[A-Z]:[\\/]|/Users/|/home/", read(path, String)) && error("本机路径泄漏")
    end
    hashes[replace(relpath(path, dir), '\\'=>'/')]=bytes2hex(sha256(read(path)))
end
manifest=joinpath(dir, "artifact-hashes.toml")
io=IOBuffer()
TOML.print(io, Dict("sha256"=>hashes); sorted = true)
text=String(take!(io))
if seal
    isfile(manifest) && error("不重封已有摘要")
    write(manifest, text)
else
    TOML.parsefile(manifest)["sha256"]==hashes || error("文件清单/哈希改变")
end
if publish
    target=joinpath(root, "docs", "src", "assets", "r4-baseline")
    for rel in vcat(sort(collect(keys(hashes))), ["artifact-hashes.toml"])
        source=joinpath(dir, rel)
        destination=joinpath(target, rel)
        if isfile(destination)
            read(source)==read(destination) || error("不覆盖不同版本的文档证据")
        else
            mkpath(dirname(destination))
            cp(source, destination)
        end
    end
end
println("R4 baseline: 13 records, A2, source data, portable paths and hashes verified.")
