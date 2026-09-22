using PaperRebuild, TOML, SHA
length(ARGS)==1 || error("参数：热模型study.toml，或旧批次study.toml")
manifest=abspath(only(ARGS))
d=TOML.parsefile(manifest)
seen=Set{String}()
for x in d["records"]
    id=x["id"]
    occursin(r"^[A-Za-z0-9_-]+$", id) && !(id in seen) || error("非法/重复运行ID")
    push!(seen, id)
    path=joinpath(dirname(manifest), id)
    bytes2hex(sha256(read(joinpath(path, "result.toml"))))==x["result_sha256"] ||
        error("原始结果变化")
    r=read_r4_run(path)
    r.case.sha256==x["input_sha256"] || error("输入身份变化")
    if d["schema"]=="r4-thermal-study-v1"
        validate_r4_thermal(r.case, r.result)==r.validation || error("重读验算不一致")
        r.result["thermal"]["loss"]==x["loss"] && r.result["thermal"]["policy"]==x["policy"] ||
            error("方法版本不一致")
    end
end
println(
    "Re-read and independently validated ",
    length(seen),
    " immutable records; original failures retained.",
)
