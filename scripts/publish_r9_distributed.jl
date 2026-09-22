# 只复制已冻结图源和图像；不启动优化，不覆盖已有文档资产。
using TOML, SHA
length(ARGS)==2 || error("usage: publish_r9_distributed.jl FIGURES NEW_DOC_ASSETS")
source, target=abspath.(ARGS)
ispath(target) && error("Do not overwrite existing assets")
config=TOML.parsefile(joinpath(source, "figure-config.toml"))
config["schema"]=="r9-distributed-figure-v1" || error("Figure schema")
config["origin"]=="synthetic" && !config["optimization_performed"] || error("Figure scope")
for (rel, digest) in config["files"]
    !isabspath(rel) && !occursin("..", rel) || error("Invalid asset path")
    dirname(rel)=="" || error("Only direct figure assets are allowed")
    bytes2hex(sha256(read(joinpath(source, rel))))==digest || error("Figure bytes changed")
end
mkpath(target)
for rel in [collect(keys(config["files"])); "figure-config.toml"]
    cp(joinpath(source, rel), joinpath(target, rel))
end
println("Copied verified figure assets without optimization: ", target)
