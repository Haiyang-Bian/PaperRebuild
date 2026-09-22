using TOML, SHA
include("r7_battery_study.jl")

function battery_pack(source, dest)
    ispath(dest)&&error("不覆盖电池公开包")
    manifest=TOML.parsefile(joinpath(source, "files.toml"))["files"]
    transport_manifest(source)==manifest || error("原报告内容改变")
    mkpath(dest)
    for p in keys(manifest)
        p=="inputs.toml" && continue
        target=joinpath(dest, split(p, '/')...)
        mkpath(dirname(target))
        cp(joinpath(source, split(p, '/')...), target)
    end
    cp(joinpath(source, "files.toml"), joinpath(dest, "original-files.toml"))
    data=read(joinpath(source, "inputs.toml"))
    paths=String[]
    # 按完整行保留原字节，避免切断UTF-8字符；片段须拼接后才能解析，不重新序列化输入。
    buffer=IOBuffer()
    function flushpart()
        p="input-parts/inputs-"*lpad(length(paths)+1, 3, '0')*".part"
        mkpath(dirname(joinpath(dest, p)))
        write(joinpath(dest, p), take!(buffer))
        push!(paths, p)
    end
    for line in eachline(IOBuffer(data); keep = true)
        ncodeunits(line)<=1_000_000 || error("输入单行过长，须另行声明分片方式")
        position(buffer)+ncodeunits(line)>1_000_000 && flushpart()
        write(buffer, line)
    end
    position(buffer)>0 && flushpart()
    write(
        joinpath(dest, "packing.toml"),
        PaperRebuild.r7_text(
            Dict(
                "schema"=>"r7-battery-public-pack-v1",
                "origin"=>"synthetic",
                "optimized_again"=>false,
                "parts"=>paths,
                "input_sha256"=>manifest["inputs.toml"],
                "input_bytes"=>length(data),
                "original_manifest_sha256"=>bytes2hex(sha256(read(joinpath(source, "files.toml")))),
                "packing_source_sha256"=>bytes2hex(sha256(read(@__FILE__))),
            ),
        ),
    )
    write(
        joinpath(dest, "files.toml"),
        PaperRebuild.r7_text(Dict("files"=>transport_manifest(dest))),
    )
    println("Oversized original inputs retained locally and packed byte for byte; no optimization.")
end

function battery_pack_check(dest)
    files=TOML.parsefile(joinpath(dest, "files.toml"))["files"]
    transport_manifest(dest)==files || error("公开包内容或文件集合改变")
    p=TOML.parsefile(joinpath(dest, "packing.toml"))
    p["schema"]=="r7-battery-public-pack-v1" && p["optimized_again"]===false ||
        error("公开包范围错误")
    p["packing_source_sha256"]==bytes2hex(sha256(read(@__FILE__))) || error("打包脚本改变")
    original=TOML.parsefile(joinpath(dest, "original-files.toml"))["files"]
    bytes2hex(sha256(read(joinpath(dest, "original-files.toml"))))==p["original_manifest_sha256"] ||
        error("原清单身份错误")
    expected=union(
        setdiff(Set(keys(original)), Set(["inputs.toml"])),
        Set(p["parts"]),
        Set(["original-files.toml", "packing.toml"]),
    )
    expected==Set(keys(files)) || error("公开包文件与原报告不对应")
    for key in keys(files)
        !isabspath(key)&&!occursin(':', key)&&all(x->!(x in ("", ".", "..")), split(key, '/')) ||
            error("公开包路径错误")
        filesize(joinpath(dest, key))<=5*1024^2 || error("公开单文件超过5MiB")
    end
    bytes=reduce(vcat, (read(joinpath(dest, name)) for name in p["parts"]))
    length(bytes)==p["input_bytes"] &&
    bytes2hex(sha256(bytes))==p["input_sha256"]==original["inputs.toml"] ||
        error("拼接输入与原字节不同")
    tmp=joinpath(BATTERY_ROOT, "tmp")
    mkpath(tmp)
    mktempdir(tmp) do stage
        for key in keys(original)
            target=joinpath(stage, split(key, '/')...)
            mkpath(dirname(target))
            key=="inputs.toml" ? write(target, bytes) : cp(joinpath(dest, key), target)
        end
        cp(joinpath(dest, "original-files.toml"), joinpath(stage, "files.toml"))
        # 完整原值由每个运行自带源码独立验证，不只检查外层清单。
        battery_check(stage)
    end
    println("Public pack reconstructed exactly and all frozen numerical evidence rechecked.")
end

if abspath(PROGRAM_FILE)==@__FILE__
    length(ARGS)==3 && ARGS[1]=="pack" ? battery_pack(abspath(ARGS[2]), abspath(ARGS[3])) :
    length(ARGS)==2 && ARGS[1]=="check" ? battery_pack_check(abspath(ARGS[2])) :
    error("usage: pack_r7_battery.jl pack ORIGINAL NEW_PUBLIC | check PUBLIC")
end
