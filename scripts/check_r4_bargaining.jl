using PaperRebuild, TOML, SHA, CSV
include("r4_bargaining_docs.jl")
sync_r4_bargaining(; check = !("--sync" in ARGS))
args=filter(x->!startswith(x, "--"), ARGS)
isempty(args) && exit()
length(args)==1 || error("提供一个报告目录")
dir=only(args)
root=normpath(joinpath(@__DIR__, ".."))
alloc=TOML.parsefile(joinpath(dir, "allocations.toml"))["records"]
length(alloc)==4 || error("本批须有两案例两权重的完整记录")
for r in alloc
    validate_r4_allocation(r["allocation"])==r["validation"] || error("分配验收不一致")
    r["validation"]["allocation_pass"] || error("分配不合格")
end
cert=TOML.parsefile(joinpath(dir, "certificates.toml"))["certificates"]
length(cert)==2 || error("局部补证记录不完整")
for r in cert
    # 未通过也允许归档负结果，禁止用报告工具把失败改为通过。
    r["local_certificate_pass"]==all(x["certificate_pass"] for x in r["local_stages"]) ||
        error("补证摘要不一致")
end
length(collect(CSV.File(joinpath(dir, "allocations.csv"))))==12 || error("主体图源缺失")
for (file, script) in
    (("report.toml", "report_r4_bargaining.jl"), ("figure-config.toml", "plot_r4_bargaining.jl"))
    TOML.parsefile(joinpath(dir, file))["script_sha256"] ==
    bytes2hex(sha256(read(joinpath(root, "scripts", script)))) || error("生成脚本变化")
end
for (file, hash) in TOML.parsefile(joinpath(dir, "figure-config.toml"))["source_sha256"]
    bytes2hex(sha256(read(joinpath(dir, file))))==hash || error("图源改变")
end
hashes=Dict{String,String}()
for (folder, _, files) in walkdir(dir), file in files
    file=="artifact-hashes.toml" && continue
    path=joinpath(folder, file)
    stat(path).size<=5*1024^2 || error("摘要过大")
    if endswith(file, ".toml") || endswith(file, ".csv")
        occursin(r"(?i)[A-Z]:[\\/]|/Users/|/home/", read(path, String)) && error("本机路径泄漏")
    end
    hashes[replace(relpath(path, dir), '\\'=>'/')]=bytes2hex(sha256(read(path)))
end
manifest=joinpath(dir, "artifact-hashes.toml")
if "--seal" in ARGS
    isfile(manifest) && error("不重封旧报告")
    write(manifest, PaperRebuild.r4_text(Dict("sha256"=>hashes)))
else
    TOML.parsefile(manifest)["sha256"]==hashes || error("报告文件变化")
end
if "--publish" in ARGS
    target=joinpath(root, "docs", "src", "assets", "r4-bargaining")
    for rel in vcat(collect(keys(hashes)), ["artifact-hashes.toml"])
        src=joinpath(dir, rel)
        dst=joinpath(target, rel)
        if isfile(dst)
            read(src)==read(dst) || error("不覆盖不同报告")
        else
            mkpath(dirname(dst))
            cp(src, dst)
        end
    end
end
println("R4 allocation/certificate/source/portable-hash report checked.")
