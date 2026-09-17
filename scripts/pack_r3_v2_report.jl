using CSV, TOML, SHA

# 全部逐公式图源保留；用已有CSV包的gzip支持减少版本库体积，不抽样或删除残差行。
length(ARGS)==1 || error("usage: pack_r3_v2_report.jl SUMMARY_DIRECTORY")
directory=abspath(only(ARGS))
isfile(joinpath(directory, "figure-config.toml")) || error("报告未生成完毕")
manifest=joinpath(directory, "packed-sources.toml")
ispath(manifest) && error("拒绝覆盖已有打包记录")
records=Dict{String,Any}[]
for folder in sort(readdir(directory; join = true))
    source=joinpath(folder, "F04-source.csv")
    isfile(source) || continue
    target=source*".gz"
    ispath(target) && error("拒绝覆盖已有压缩图源")
    before=CSV.File(source)
    CSV.write(target, before; compress = true)
    after=CSV.File(target)
    propertynames(before)==propertynames(after) && length(before)==length(after) ||
        error("压缩重读结构不同")
    all(isequal(getproperty(before, k), getproperty(after, k)) for k in propertynames(before)) ||
        error("压缩重读数值不同")
    push!(
        records,
        Dict(
            "file"=>replace(relpath(target, directory), '\\'=>'/'),
            "rows"=>length(before),
            "source_sha256"=>bytes2hex(sha256(read(source))),
            "packed_sha256"=>bytes2hex(sha256(read(target))),
            "all_values_roundtrip"=>true,
        ),
    )
end
open(
    io->TOML.print(io, Dict("sources"=>records, "lossless_values"=>true); sorted = true),
    manifest,
    "w",
)
println("Packed and verified ", length(records), " complete residual sources.")
