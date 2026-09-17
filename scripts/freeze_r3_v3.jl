include("r3_setup.jl")
inputs="results/summaries/r3-v2/r3-v2-combined-20260917T095056-767e69d2/inputs"
studyfile="results/runs/r3-v2-combined-20260917T095056/study.toml"
old=TOML.parsefile(studyfile);
source=TOML.parsefile(joinpath(inputs, "manifest.toml"))
entries=Dict{String,Any}[]
for e in source["runs"]
    e["group"]=="robustness" || get(e, "method", "")=="pg" || continue
    row=deepcopy(e)
    case=load_r2_case(joinpath(inputs, e["case_file"]))
    case.sha256==e["input_sha256"] || error("输入哈希改变")
    entry=only(x for x in old["runs"] if x["id"]==e["id"])
    path=normpath(joinpath(dirname(studyfile), entry["directory"], "run.toml"))
    open(path) do io
        bytes2hex(sha256(io))==e["run_sha256"] || error("历史运行哈希不一致")
    end
    # 仅解析TOML根字段；不读取数百MB逐轮对偶表。完整文件哈希已核对。
    lines=String[]
    for line in eachline(path)
        startswith(line, "[") && break
        push!(lines, line)
    end
    header=TOML.parse(join(lines, "\n"))
    row["initial_flow"]=header["initial_flow"]
    row["initial_flow_sha256"]=header["initial_flow_sha256"]
    PaperRebuild.r2_flow_hash(PaperRebuild.r3_matrix(row["initial_flow"]))==row["initial_flow_sha256"] ||
        error("初值哈希改变")
    row["case_path"]=replace(joinpath(inputs, e["case_file"]), '\\'=>'/')
    row["v2_directory"]=replace(dirname(path), '\\'=>'/')
    row["physical_recovery"]=true
    row["stationarity_check"]=true
    push!(entries, row)
end
length(entries)==24 || error("需要16+8项")
for id in ("two-source-VF_CT-pg", "two-source-schpd", "single-delay-switch"),
    flag in ("physical_recovery", "stationarity_check")

    row=deepcopy(only(x for x in entries if x["id"]==id))
    row["paired_id"]=id
    row["id"]=id*"-without-"*replace(flag, '_'=>'-')
    row["group"]="ablation"
    row[flag]=false
    push!(entries, row)
end
target="configs/r3/v3-study.toml"
isfile(target) && error("冻结清单已存在，不覆盖")
open(
    io->TOML.print(
        io,
        Dict(
            "schema"=>"r3-v3-study-inputs-v1",
            "origin"=>"synthetic",
            "algorithm"=>"r3_pg_checked_v3",
            "budget_sec"=>600.0,
            "max_iterations"=>200,
            "entries"=>entries,
            "prior_study"=>studyfile,
        );
        sorted = true,
    ),
    target,
    "w",
)
println("Frozen 24+6 exact historical initial flows: ", target)
