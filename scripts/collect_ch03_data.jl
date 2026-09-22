# 下载公开输入，原始字节只写入按SHA-256命名的目录；不覆盖已有数据。
using Dates, Downloads, SHA, TOML

root = normpath(joinpath(@__DIR__, ".."))
registry = TOML.parsefile(joinpath(root, "docs", "reading", "ch03", "sources.toml"))
rawroot = joinpath(root, "data", "raw", "ch03")
mkpath(rawroot)
receipts = Any[]
for source in registry["sources"]
    get(source, "required", true) || ("--include-optional" in ARGS) || continue
    id, filename = source["id"], source["filename"]
    receiptfile = joinpath(rawroot, id, "receipt.toml")
    if isfile(receiptfile)
        receipt = TOML.parsefile(receiptfile)
        path = joinpath(root, receipt["path"])
        bytes2hex(sha256(read(path))) == receipt["sha256"] || error("缓存哈希不符：$id")
        get(source, "sha256", receipt["sha256"]) == receipt["sha256"] ||
            error("来源锁定哈希不符：$id")
        receipt["url"] == source["url"] || error("URL已变更：新增来源ID，勿复用旧回执")
        push!(receipts, receipt)
        println("CACHED ", id, " ", receipt["sha256"])
        continue
    end
    temporary = tempname(rawroot)
    try
        Downloads.download(source["url"], temporary; timeout = 60)
        bytes = read(temporary)
        isempty(bytes) && error("下载为空")
        haskey(source, "expected_bytes") &&
            length(bytes) != source["expected_bytes"] &&
            error("下载长度与发布元数据不符")
        if source["kind"] == "xlsx"
            bytes[1:2] == UInt8[0x50, 0x4b] || error("不是XLSX ZIP格式")
        elseif source["kind"] == "pdf"
            startswith(String(bytes[1:min(end, 5)]), "%PDF-") || error("不是PDF")
        end
        digest = bytes2hex(sha256(bytes))
        get(source, "sha256", digest) == digest || error("发布字节已变化，拒绝复用旧来源版本")
        folder = joinpath(rawroot, id, digest)
        mkpath(folder)
        path = joinpath(folder, filename)
        isfile(path) ? (read(path) == bytes || error("已有文件内容冲突")) : mv(temporary, path)
        receipt = Dict(
            "id" => id,
            "url" => source["url"],
            "sha256" => digest,
            "bytes" => length(bytes),
            "retrieved_utc" => string(now(UTC)),
            "path" => replace(relpath(path, root), '\\' => '/'),
            "status" => "downloaded",
        )
        receipt_tmp = tempname(dirname(receiptfile))
        open(receipt_tmp, "w") do io
            TOML.print(io, receipt; sorted = true)
        end
        mv(receipt_tmp, receiptfile)
        push!(receipts, receipt)
        println("DOWNLOADED ", id, " ", length(bytes), " bytes ", digest)
    catch error
        # 网络失败显式保留；其他独立来源仍可继续。
        push!(receipts, Dict("id" => id, "status" => "failed", "error" => sprint(showerror, error)))
        @warn "获取失败" id exception = error
    finally
        isfile(temporary) && rm(temporary)
    end
end
any(r -> r["status"] == "failed", receipts) && exit(1)
