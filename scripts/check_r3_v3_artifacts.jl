using TOML, CSV, SHA, PaperRebuild

# 不求解：校验正式摘要的冻结输入、科学源码、完整压缩图源与状态语义。
length(ARGS)==1 || error("usage: check_r3_v3_artifacts.jl SUMMARY_DIRECTORY")
folder=abspath(only(ARGS))
root=normpath(joinpath(@__DIR__, ".."))
mapping=TOML.parsefile(joinpath(root, "docs", "reading", "ch03", "r3-v3-formulations.toml"))
page=read(joinpath(root, "docs", "src", "ch03-r3-v3.md"), String)
for e in mapping["equations"]
    isdefined(PaperRebuild, Symbol(e["api"])) || error("API映射失效")
    isfile(joinpath(root, e["source"])) || error("源码映射失效")
    occursin(e["test"], read(joinpath(root, e["test_file"]), String)) || error("测试映射失效")
    occursin("\\tag{"*e["id"]*"}", page) || error("编号公式缺失")
end
rows=collect(CSV.File(joinpath(folder, "comparison.csv")))
entries=TOML.parsefile(joinpath(folder, "frozen.toml"))["entries"]
provenance=TOML.parsefile(joinpath(folder, "provenance.toml"))["runs"]
length(rows)==length(entries)==length(provenance)==30 || error("运行清单缺项")
Set(x.id for x in rows)==Set(x["id"] for x in entries)==Set(x["id"] for x in provenance) ||
    error("条目ID不匹配")
all(x.group in ("robustness", "modes", "ablation") for x in rows) || error("未知实验组")
count(x.group=="robustness" for x in rows)==16 || error("稳健性组缺项")
count(x.group=="modes" for x in rows)==8 || error("模式组缺项")
count(x.group=="ablation" for x in rows)==6 || error("消融组缺项")
for r in rows
    e=only(x for x in entries if x["id"]==r.id)
    p=only(x for x in provenance if x["id"]==r.id)
    r.input_sha256==p["input_sha256"]==e["input_sha256"] || error("输入哈希不匹配: $(r.id)")
    bytes2hex(sha256(read(joinpath(root, e["case_path"]))))==r.input_sha256 ||
        error("案例输入被改写")
    r.initial_flow_sha256==e["initial_flow_sha256"] || error("初值不匹配")
    r.physical_recovery==e["physical_recovery"] && r.stationarity_check==e["stationarity_check"] ||
        error("消融开关改变")
    r.physical_pass==!ismissing(r.cost) || error("费用与物理候选状态不同")
    if r.local_stationarity_checked
        r.stationarity_check &&
        r.outer_status=="local_stationarity_checked" &&
        !r.outer_converged || error("驻点与原停止语义混用")
    end
    if r.final_objective_kind=="physical_violation"
        r.physical_pass && !r.cost_optimization_complete || error("恢复目标被误当费用最优")
    end
    for (path, hash) in p["source_hashes"]
        startswith(path, "src/") || continue
        bytes2hex(sha256(read(joinpath(root, path))))==hash || error("科学源码不同: $path")
    end
end
packed=TOML.parsefile(joinpath(folder, "packed-sources.toml"))
length(packed["sources"])==30 || error("完整残差图源缺项")
for s in packed["sources"]
    path=joinpath(folder, s["file"])
    bytes2hex(sha256(read(path)))==s["packed_sha256"] || error("压缩图源被改写")
    length(CSV.File(path))==s["rows"] && s["all_values_roundtrip"] || error("压缩图源记录不符")
end
println("3条项目补充公式映射、30例冻结输入/初值、v3源码、消融与状态语义、全部压缩残差校验通过。")
