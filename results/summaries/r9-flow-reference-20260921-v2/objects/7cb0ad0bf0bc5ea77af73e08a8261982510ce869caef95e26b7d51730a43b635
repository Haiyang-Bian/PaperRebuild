"""
    save_r1_run(case, result; root="results/runs", run_id=...)

创建独立且不可覆盖的运行目录，保存显式配置、求解状态/预算/界、输入哈希、解、独立残差和环境版本。
CSV 用于图源，TOML 用于无损重读；无解运行仍保留状态但不生成假解。返回目录。
"""
function save_r1_run(
    c::R1Case,
    result;
    root = "results/runs",
    run_id = "r1-" * Dates.format(now(UTC), "yyyymmddTHHMMSS") * "-" * string(uuid4())[1:8],
)
    occursin(r"^[A-Za-z0-9_-]+$", run_id) || throw(ArgumentError("运行 ID 不能包含路径"))
    dir = joinpath(root, run_id)
    mkpath(root)
    mkdir(dir) # 已存在则失败，不覆盖旧结果。
    write_toml(name, x) = open(io -> TOML.print(io, x; sorted = true), joinpath(dir, name), "w")
    write_toml("case.toml", c.data)
    write_toml("solution.toml", result)
    pkgroot = normpath(joinpath(@__DIR__, "..", ".."))
    hashes = Dict{String,Any}()
    for path in ("Project.toml", "Manifest.toml", "docs/Project.toml", "docs/Manifest.toml")
        hashes[path] = bytes2hex(sha256(read(joinpath(pkgroot, path))))
    end
    for (dirpath, _, files) in walkdir(joinpath(pkgroot, "src")), file in files
        endswith(file, ".jl") || continue
        path = joinpath(dirpath, file)
        hashes[replace(relpath(path, pkgroot), '\\' => '/')] = bytes2hex(sha256(read(path)))
    end
    metadata = Dict(
        "run_id" => run_id,
        "julia" => string(VERSION),
        "created_utc" => string(now(UTC)),
        "source_input_sha256" => c.sha256,
        "saved_case_sha256" => bytes2hex(sha256(read(joinpath(dir, "case.toml")))),
        "solution_sha256" => bytes2hex(sha256(read(joinpath(dir, "solution.toml")))),
        "hashes" => hashes,
        "origin" => "synthetic",
        "randomness" => "none",
        "scope" => "ch02 fixed-flow two-node subset",
    )
    write_toml("metadata.toml", metadata)
    report = validate_r1_solution(c, result)
    write_toml(
        "validation.toml",
        Dict(
            "status" => report.status,
            "relaxed_pass" => report.relaxed_pass,
            "original_branch_pass" => report.original_branch_pass,
        ),
    )
    if haskey(result, "values")
        CSV.write(joinpath(dir, "residuals.csv"), report.rows)
        T, s = c.data["time"]["T"], result["values"]
        fields = sort([k for (k, v) in s if v isa AbstractVector && length(v) == T])
        records = [
            merge(
                (t = t, time_h = t * c.data["time"]["dt_h"]),
                NamedTuple{Tuple(Symbol.(fields))}(Tuple(s[k][t] for k in fields)),
            ) for t in 1:T
        ]
        CSV.write(joinpath(dir, "timeseries.csv"), records)
        CSV.write(
            joinpath(dir, "states.csv"),
            [
                (
                    t = t,
                    time_h = t * c.data["time"]["dt_h"],
                    E_BS = s["E_BS"][t+1],
                    E_HS = s["E_HS"][t+1],
                    tau_IN = s["tau_IN"][t+1],
                ) for t in 0:T
            ],
        )
    end
    return dir
end

"""
    read_r1_run(dir)

读取保存的案例和解，校验规范化输入副本的 SHA-256，再恢复原始输入哈希关联。
不重新求解；返回 `(case, result, metadata)`，可交给独立验证或重绘程序。
"""
function read_r1_run(dir)
    meta = TOML.parsefile(joinpath(dir, "metadata.toml"))
    c = load_case(joinpath(dir, "case.toml"))
    c.sha256 == meta["saved_case_sha256"] || throw(ArgumentError("保存的案例已发生变化"))
    if haskey(meta, "solution_sha256")
        bytes2hex(sha256(read(joinpath(dir, "solution.toml")))) == meta["solution_sha256"] ||
            throw(ArgumentError("保存的解已发生变化"))
    end
    result = TOML.parsefile(joinpath(dir, "solution.toml"))
    result["input_sha256"] == meta["source_input_sha256"] ||
        throw(ArgumentError("输入来源关联失效"))
    return (case = R1Case(c.data, meta["source_input_sha256"]), result = result, metadata = meta)
end

"""
    plot_r1_run(dir; output=joinpath(dir, "figures"))

读取保存结果绘制 F01—F04；由独立脚本 `scripts/plot_r1.jl` 加载 CairoMakie 后提供方法。
根模块导入不加载绘图库、不申请求解器许可；图源与绘图配置随图保存，不重新求解。
"""
function plot_r1_run end
