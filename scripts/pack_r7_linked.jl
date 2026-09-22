using TOML, SHA
include("r7_linked_study.jl")

"""只分片超过5MiB的原文件；不删残差、不重新序列化、不覆盖本地原报告。"""
function linked_pack(source, dest)
    ispath(dest)&&error("不覆盖详细规划公开包")
    original=TOML.parsefile(joinpath(source, "files.toml"))["files"]
    transport_manifest(source)==original || error("原报告改变")
    mkpath(dest)
    entries=Any[]
    for path in sort(collect(keys(original)))
        file=joinpath(source, split(path, '/')...)
        if filesize(file)<=5*1024^2
            target=joinpath(dest, split(path, '/')...)
            mkpath(dirname(target))
            cp(file, target)
            continue
        end
        paths=String[]
        buffer=IOBuffer()
        function flushpart()
            name="parts/"*lpad(length(entries)+1, 3, '0')*"/chunk-"*lpad(length(paths)+1, 3, '0')*".part"
            mkpath(dirname(joinpath(dest, name)))
            write(joinpath(dest, name), take!(buffer))
            push!(paths, name)
        end
        for line in eachline(file; keep = true)
            ncodeunits(line)<=1_000_000 || error("单行过长，须另立分片规则")
            position(buffer)+ncodeunits(line)>1_000_000&&flushpart()
            write(buffer, line)
        end
        position(buffer)>0&&flushpart()
        push!(
            entries,
            Dict("path"=>path, "parts"=>paths, "bytes"=>filesize(file), "sha256"=>original[path]),
        )
    end
    cp(joinpath(source, "files.toml"), joinpath(dest, "original-files.toml"))
    write(
        joinpath(dest, "packing.toml"),
        PaperRebuild.r7_text(
            Dict(
                "schema"=>"r7-linked-public-pack-v1",
                "origin"=>"synthetic",
                "optimized_again"=>false,
                "entries"=>entries,
                "original_manifest_sha256"=>bytes2hex(sha256(read(joinpath(source, "files.toml")))),
                "packing_source_sha256"=>bytes2hex(sha256(read(@__FILE__))),
            ),
        ),
    )
    write(
        joinpath(dest, "files.toml"),
        PaperRebuild.r7_text(Dict("files"=>transport_manifest(dest))),
    )
    println("Detailed planning oversized original files partitioned byte for byte.")
end

function linked_pack_check(dest)
    files=TOML.parsefile(joinpath(dest, "files.toml"))["files"]
    transport_manifest(dest)==files || error("详细规划公开包改变")
    p=TOML.parsefile(joinpath(dest, "packing.toml"))
    p["schema"]=="r7-linked-public-pack-v1"&&p["optimized_again"]===false&&p["origin"]=="synthetic" ||
        error("公开包范围错误")
    p["packing_source_sha256"]==bytes2hex(sha256(read(@__FILE__))) || error("打包源码改变")
    original=TOML.parsefile(joinpath(dest, "original-files.toml"))["files"]
    bytes2hex(sha256(read(joinpath(dest, "original-files.toml"))))==p["original_manifest_sha256"] ||
        error("原清单身份错误")
    entries=Dict(e["path"]=>e for e in p["entries"])
    length(entries)==length(p["entries"])&&all(k->k in keys(original), keys(entries)) ||
        error("分片身份错误")
    parts=reduce(vcat, [e["parts"] for e in p["entries"]]; init = String[])
    length(parts)==length(unique(parts)) || error("分片重复")
    expected=union(
        setdiff(Set(keys(original)), Set(keys(entries))),
        Set(parts),
        Set(["original-files.toml", "packing.toml"]),
    )
    expected==Set(keys(files)) || error("公开文件与原报告不对应")
    for key in union(Set(keys(files)), Set(keys(original)))
        !isabspath(key)&&!occursin(':', key)&&!occursin('\\', key)&&all(
            x->!(x in ("", ".", "..")),
            split(key, '/'),
        ) || error("公开路径非法")
    end
    all(filesize(joinpath(dest, key))<=5*1024^2 for key in keys(files)) || error("公开文件超过限制")
    # 重建仅发生在项目tmp的唯一临时目录；数值检查调用各运行随附的冻结源码。
    mktempdir(joinpath(LINKED_ROOT, "tmp")) do stage
        for key in keys(original)
            target=joinpath(stage, split(key, '/')...)
            mkpath(dirname(target))
            if haskey(entries, key)
                e=entries[key]
                bytes=reduce(vcat, [read(joinpath(dest, name)) for name in e["parts"]])
                length(bytes)==e["bytes"]&&bytes2hex(sha256(bytes))==e["sha256"]==original[key] ||
                    error("拼接后不是原字节")
                write(target, bytes)
            else
                cp(joinpath(dest, key), target)
            end
        end
        cp(joinpath(dest, "original-files.toml"), joinpath(stage, "files.toml"))
        linked_check(stage)
    end
    println(
        "Public linked planning evidence reconstructed exactly and revalidated; no optimization.",
    )
end

if abspath(PROGRAM_FILE)==@__FILE__
    length(ARGS)==3&&ARGS[1]=="pack" ? linked_pack(abspath(ARGS[2]), abspath(ARGS[3])) :
    length(ARGS)==2&&ARGS[1]=="check" ? linked_pack_check(abspath(ARGS[2])) :
    error("usage: pack_r7_linked.jl pack ORIGINAL NEW_PUBLIC | check PUBLIC")
end
