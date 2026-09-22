# 复制已保存原字节并建立来源清单；不移动/覆盖输入，不重新求解。
using TOML, SHA
length(ARGS) == 4 || error("usage: archive_r9_numerics.jl BATCH REPORT DIAGNOSTIC_ROOT NEW_AUDIT")
batch, report, source, audit = abspath.(ARGS)
root = normpath(joinpath(@__DIR__, ".."))
hashfile(p) = bytes2hex(sha256(read(p)))
destinations = [joinpath(root, "results/summaries", basename(p)) for p in (batch, report)]
all(!ispath, [destinations; audit]) || error("不覆盖归档")
for (src, dst) in zip((batch, report), destinations)
    cp(src, dst)
    for (dir, _, names) in walkdir(src), name in names
        p = relpath(joinpath(dir, name), src)
        read(joinpath(src, p)) == read(joinpath(dst, p)) || error("归档字节改变")
    end
end
mkpath(audit)
folders = Dict(
    "terminal-conditioning-v1"=>"terminal-matrix",
    "terminal-exact-v3"=>"terminal-exact",
    "original-affine-exact-v1"=>"original-ct",
    "original-affine-check-v1"=>"original-ct-check",
    "original-affine-vt-exact-v1"=>"original-vt",
    "original-affine-vt-check-v1"=>"original-vt-check",
)
for (src, dst) in folders
    cp(joinpath(source, src), joinpath(audit, dst))
end
cp(joinpath(@__DIR__, "r9_pv_study.jl"), joinpath(audit, "r9_pv_study.jl"))
cp(
    joinpath(@__DIR__, "check_r9_affine_certificate.jl"),
    joinpath(audit, "check_r9_affine_certificate.jl"),
)
cp(@__FILE__, joinpath(audit, "archive-source.jl"))
files = Dict(
    replace(relpath(joinpath(dir, n), audit), '\\'=>'/')=>hashfile(joinpath(dir, n)) for
    (dir, _, names) in walkdir(audit) for n in names
)
open(joinpath(audit, "manifest.toml"), "w") do io
    TOML.print(
        io,
        Dict(
            "schema"=>"r9-numerics-audit-v1",
            "origin"=>"synthetic",
            "parent_batch"=>"r9-pv-batch-20260920-v4",
            "new_batch"=>basename(batch),
            "new_manifest_sha256"=>hashfile(joinpath(batch, "manifest.toml")),
            "scope"=>"exact binary certificates; not physical impossibility",
            "files"=>files,
        );
        sorted = true,
    )
end
println("Archived original bytes: ", join(basename.(destinations), ", "), "; ", basename(audit))
