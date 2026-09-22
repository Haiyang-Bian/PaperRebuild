include("r5_market_payment_tables.jl")
include("r5_risk_artifact_paths.jl")
args=filter(x->!startswith(x, "--"), ARGS)
length(args)==1||error("参数：支付审计目录 [--seal] [--publish]")
dir=abspath(only(args));
root=normpath(joinpath(@__DIR__, ".."))
meta=TOML.parsefile(joinpath(dir, "report.toml"))
meta["schema"]=="r5-market-payment-report-v1"&&meta["origin"]=="synthetic"&&!meta["solver_reexecuted"]||error(
    "支付报告身份错误",
)
for (path, hash) in meta["source_sha256"]
    bytes2hex(sha256(read(joinpath(root, split(path, '/')...))))==hash||error("支付科学源码改变")
end
for (file, hash) in meta["producer_sha256"]
    bytes2hex(sha256(read(joinpath(@__DIR__, file))))==hash||error("支付生成器改变")
end
Set(readdir(joinpath(dir, "witnesses")))==Set(keys(meta["witness_sha256"]))||error(
    "支付见证清单不同",
)
witnesses=Dict{String,Any}[]
for file in sort!(collect(keys(meta["witness_sha256"])))
    path=joinpath(dir, "witnesses", file)
    bytes2hex(sha256(read(path)))==meta["witness_sha256"][file]||error("支付见证篡改")
    w=TOML.parsefile(path)
    w["schema"]=="r5-market-payment-witness-v1"&&file==w["record_id"]*".toml"||error(
        "支付见证身份错误",
    )
    push!(witnesses, w)
end
tables=r5_market_payment_tables(witnesses)
rules=TOML.parsefile(joinpath(root, "configs", "r5", "market", "study.toml"))
Set(x.record_id for x in tables["comparison.csv"])==Set(x["id"] for x in rules["records"]) &&
length(witnesses)==meta["records"]==18||error("原市场范围不完整")
for (file, rows) in tables
    io=IOBuffer()
    CSV.write(io, rows)
    take!(io)==read(joinpath(dir, file))||error("支付CSV并非回算值")
end
count(x->x.valid, tables["comparison.csv"])==meta["valid"]||error("支付汇总不同")
hashes=Dict{String,String}()
for (base, _, fs) in walkdir(dir), file in fs
    file=="artifact-hashes.toml"&&continue
    path=joinpath(base, file)
    islink(path)&&error("不允许链接")
    filesize(path)<5*1024^2||error("支付公开文件过大")
    (endswith(file, ".toml")||endswith(file, ".csv"))&&r5_risk_has_host_path(read(path, String))&&error(
        "支付资产含本机路径",
    )
    hashes[replace(relpath(path, dir), '\\'=>'/')]=bytes2hex(sha256(read(path)))
end
seal=joinpath(dir, "artifact-hashes.toml")
if "--seal" in ARGS
    ispath(seal)&&error("不覆盖支付封存")
    write(seal, PaperRebuild.r5_market_text(Dict("sha256"=>hashes)))
else
    TOML.parsefile(seal)["sha256"]==hashes||error("支付封存变化")
end
if "--publish" in ARGS
    target=joinpath(root, "docs", "src", "assets", "r5-market-payment")
    for rel in vcat(collect(keys(hashes)), ["artifact-hashes.toml"])
        src=joinpath(dir, split(rel, '/')...)
        dst=joinpath(target, split(rel, '/')...)
        if ispath(dst)
            read(src)==read(dst)||error("不覆盖支付文档资产")
        else
            mkpath(dirname(dst))
            cp(src, dst)
        end
    end
end
println("Payment public witness replay passed: ", meta["valid"], "/18; old failures retained.")
