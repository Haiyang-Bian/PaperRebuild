include("r3_setup.jl")

# 公开小体积的精确案例与初值；完整多阶段运行仍留在原目录，不裁剪或改写。
length(ARGS)==2 || error("usage: export_r3_v2_inputs.jl STUDY_TOML SUMMARY_DIRECTORY")
study_path, summary = abspath.(ARGS)
study = TOML.parsefile(study_path)
destination = joinpath(summary, "inputs")
ispath(destination) && error("拒绝覆盖已导出的输入")
mkpath(destination)
records = Dict{String,Any}[]
for entry in study["runs"]
    directory = normpath(joinpath(dirname(study_path), entry["directory"]))
    meta = TOML.parsefile(joinpath(directory, "metadata.toml"))
    runpath = joinpath(directory, "run.toml")
    open(io->bytes2hex(sha256(io)), runpath)==meta["artifacts"]["run.toml"] || error("运行哈希失配")
    lines = String[]
    for line in eachline(runpath)
        startswith(line, "[") && break
        push!(lines, line)
    end
    header = TOML.parse(join(lines, "\n"))
    casepath = joinpath(directory, "case.toml")
    c = load_r2_case(casepath)
    c.sha256==meta["input_sha256"] || error("案例哈希失配")
    filename = entry["id"]*".toml"
    cp(casepath, joinpath(destination, filename))
    record = Dict{String,Any}(
        "id"=>entry["id"],
        "group"=>entry["group"],
        "case_file"=>filename,
        "input_sha256"=>c.sha256,
        "run_sha256"=>meta["artifacts"]["run.toml"],
        "budget_sec"=>header["budget_sec"],
        "source_run_id"=>meta["run_id"],
    )
    if entry["group"]=="robustness"
        m = PaperRebuild.r2_flow_matrix(c, header["initial_flow"])
        PaperRebuild.r2_flow_hash(m)==header["initial_flow_sha256"] || error("初值哈希失配")
        for key in ("initial_flow", "initial_flow_sha256", "local_halfspace", "max_iterations")
            record[key]=header[key]
        end
    else
        record["mode"], record["method"] = entry["mode"], entry["method"]
        record["max_iterations"] = get(header, "max_iterations", 200)
    end
    push!(records, record)
end
open(joinpath(destination, "manifest.toml"), "w") do io
    TOML.print(
        io,
        Dict(
            "schema"=>"r3-v2-replay-inputs-v1",
            "origin"=>"synthetic",
            "batch"=>study["batch"],
            "runs"=>records,
        );
        sorted = true,
    )
end
println("Exported and hash-checked ", length(records), " replay inputs.")
