include("r3_setup.jl")
length(ARGS)==2 || error("usage: merge_r3_v2_studies.jl ROBUSTNESS_STUDY MODES_STUDY")
studies=TOML.parsefile.(ARGS)
studies[1]["config_sha256"]==studies[2]["config_sha256"] || error("两组实验配置不同")
frozen=[TOML.parsefile(joinpath(dirname(p), "frozen.toml")) for p in ARGS]
frozen[1]==frozen[2] || error("冻结清单不同")
records=Dict{String,Any}[]
root=joinpath("results", "runs", "r3-v2-combined-"*Dates.format(now(UTC), "yyyymmddTHHMMSS"))
ispath(root) && error("禁止覆盖旧批次")
for (file, s) in zip(ARGS, studies), entry in s["runs"]
    r=deepcopy(entry)
    r["directory"]=replace(relpath(joinpath(dirname(file), entry["directory"]), root), '\\'=>'/')
    push!(records, r)
end
length(records)==32 && length(unique(r["id"] for r in records))==32 || error("正式32例不完整或重复")
mkdir(root)
for file in ("frozen.toml", "config.toml")
    cp(joinpath(dirname(first(ARGS)), file), joinpath(root, file))
end
merged=Dict(
    "batch"=>basename(root),
    "schema"=>"r3-v2-study-v1",
    "origin"=>"synthetic",
    "runs"=>records,
    "config_sha256"=>studies[1]["config_sha256"],
    "component_batches"=>[s["batch"] for s in studies],
)
path=joinpath(root, "study.toml")
open(io->TOML.print(io, merged; sorted = true), path, "w")
println(path)
