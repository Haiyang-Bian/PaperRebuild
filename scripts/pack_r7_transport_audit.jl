using CSV, TOML, SHA
include("audit_r7_transport.jl")

"""将过大的残差CSV按完整行拆分；拼接后必须与原CSV逐字节相同，不删除原审计。"""
function pack_transport_audit(src, out)
    ispath(out) && error("不覆盖公开审计")
    old = TOML.parsefile(joinpath(src, "audit.toml"))
    for (p, h) in old["files"]
        bytes2hex(sha256(read(joinpath(src, p)))) == h || error("原审计内容改变")
    end
    lines = readlines(joinpath(src, "residuals.csv"); keep = true)
    parts = String[]
    mkpath(out)
    for (n, first) in enumerate(2:10000:length(lines))
        path = "residuals-" * lpad(n, 3, '0') * ".csv"
        write(joinpath(out, path), lines[1] * join(lines[first:min(first+9999, length(lines))]))
        push!(parts, path)
    end
    cp(joinpath(src, "validation-summary.csv"), joinpath(out, "validation-summary.csv"))
    cp(joinpath(src, "audit.toml"), joinpath(out, "original-audit.toml"))
    files = Dict(p => bytes2hex(sha256(read(joinpath(out, p)))) for p in readdir(out))
    meta = Dict(
        "schema" => "r7-transport-public-audit-v1",
        "origin" => "synthetic",
        "solver_called" => false,
        "parts" => parts,
        "files" => files,
        "original_residual_sha256" => old["files"]["residuals.csv"],
        "source_sha256" => bytes2hex(sha256(read(@__FILE__))),
    )
    write(joinpath(out, "pack.toml"), PaperRebuild.r7_text(meta))
    println("Original audit preserved; residual CSV partitioned without numerical or byte changes.")
end

function check_transport_audit_pack(src, out)
    meta = TOML.parsefile(joinpath(out, "pack.toml"))
    meta["source_sha256"] == bytes2hex(sha256(read(@__FILE__))) || error("拆分入口改变")
    Set(readdir(out)) == union(Set(keys(meta["files"])), Set(["pack.toml"])) ||
        error("公开审计文件集合改变")
    for (p, h) in meta["files"]
        bytes2hex(sha256(read(joinpath(out, p)))) == h || error("公开审计内容改变")
    end
    bytes = IOBuffer()
    header = nothing
    for (i, p) in enumerate(meta["parts"])
        lines = readlines(joinpath(out, p); keep = true)
        i == 1 && (header = lines[1])
        lines[1] == header || error("残差表头不一致")
        i == 1 && write(bytes, header)
        write(bytes, join(lines[2:end]))
    end
    joined = take!(bytes)
    bytes2hex(sha256(joined)) == meta["original_residual_sha256"] || error("拼接字节与原残差不同")
    tables = transport_audit_tables(src)
    joined == transport_csv_bytes(tables["residuals.csv"]) || error("公开残差与原记录回代不同")
    read(joinpath(out, "validation-summary.csv")) ==
    transport_csv_bytes(tables["validation-summary.csv"]) || error("公开摘要与回代不同")
    old = TOML.parsefile(joinpath(out, "original-audit.toml"))
    old["report_manifest_sha256"] == bytes2hex(sha256(read(joinpath(src, "files.toml")))) ||
        error("原报告身份不同")
    old["audit_source_sha256"] ==
    bytes2hex(sha256(read(joinpath(@__DIR__, "audit_r7_transport.jl")))) || error("审计入口不同")
    println(
        "Partitioned audit checked against frozen-source original values; no oversized file or reoptimization.",
    )
end

length(ARGS) == 3 && ARGS[1] in ("pack", "check") ||
    error("usage: pack_r7_transport_audit.jl pack ORIGINAL_AUDIT NEW_PUBLIC | check REPORT PUBLIC")
if ARGS[1] == "pack"
    pack_transport_audit(abspath(ARGS[2]), abspath(ARGS[3]))
else
    check_transport_audit_pack(abspath(ARGS[2]), abspath(ARGS[3]))
end
