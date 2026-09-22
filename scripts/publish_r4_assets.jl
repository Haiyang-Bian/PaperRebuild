# 只复制已封存的本地摘要到Documenter；不发布远程、不重绘、不求解。
using TOML, SHA
root=normpath(joinpath(@__DIR__, ".."))
source=joinpath(root, "results", "summaries", "r4-first-batch")
target=joinpath(root, "docs", "src", "assets", "r4-first-batch")
hashes=TOML.parsefile(joinpath(source, "artifact-hashes.toml"))["sha256"]
for (rel, hash) in hashes
    bytes2hex(sha256(read(joinpath(source, rel))))==hash || error("摘要哈希不符")
    dest=joinpath(target, rel)
    if isfile(dest)
        bytes2hex(sha256(read(dest)))==hash || error("不覆盖不同版本文档图源")
    else
        mkpath(dirname(dest))
        cp(joinpath(source, rel), dest)
    end
end
manifest=joinpath(target, "artifact-hashes.toml")
if isfile(manifest)
    read(manifest)==read(joinpath(source, "artifact-hashes.toml")) || error("文档清单与封存不符")
else
    cp(joinpath(source, "artifact-hashes.toml"), manifest)
end
println("R4 sealed evidence copied to Documenter assets.")
