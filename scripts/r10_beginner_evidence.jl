"""R10入门证据的封存与只读重验；冻结R1独立验证器，不加载优化器。"""
module R10BeginnerEvidence
using TOML, SHA

const R1_SOURCES = [
    "src/components/devices.jl",
    "src/networks/fixed_flow_heat.jl",
    "src/core/case.jl",
    "src/verification/r1.jl",
]
const RUN_FILES = [
    "case.toml",
    "solution.toml",
    "metadata.toml",
    "validation.toml",
    "residuals.csv",
    "timeseries.csv",
    "states.csv",
]
const ENV_FILES =
    [joinpath(d, f) for d in ("", "docs", "tools") for f in ("Project.toml", "Manifest.toml")]
sha(path) = bytes2hex(open(sha256, path))
toml(path) = TOML.parsefile(path)
write_toml(path, x) = open(io -> TOML.print(io, x; sorted = true), path, "w")

function safe(root, relative)
    parts = split(replace(relative, '\\' => '/'), '/')
    isempty(parts) || any(p -> isempty(p) || p in (".", "..") || occursin(':', p), parts) ?
    error("Unsafe evidence path") : joinpath(root, parts...)
end

function files(root)
    sort([
        replace(relpath(joinpath(d, f), root), '\\' => '/') for (d, _, fs) in walkdir(root) for
        f in fs
    ])
end

function sign(root)
    paths = filter(!=("artifact-hashes.toml"), files(root))
    write_toml(
        joinpath(root, "artifact-hashes.toml"),
        Dict(
            "schema" => "r10-beginner-hashes-v1",
            "files" => Dict(p => sha(safe(root, p)) for p in paths),
        ),
    )
end

"""
    check(root)

验证文件身份，并用冻结R1源码从保存的原控制量重算全部方程、边界、成本和逐项残差。
只用Julia标准库，不重新求解。验收限于该合成R1特例；文件完整不能替代全文科学验收。
"""
function check(root)
    root = abspath(root)
    manifest = toml(joinpath(root, "artifact-hashes.toml"))
    manifest["schema"] == "r10-beginner-hashes-v1" || error("Unknown evidence schema")
    expected = manifest["files"]
    paths = filter(!=("artifact-hashes.toml"), files(root))
    Set(paths) == Set(keys(expected)) || error("Missing or extra evidence files")
    for (p, h) in expected
        sha(safe(root, p)) == h || error("Changed evidence: " * p)
    end
    required = vcat(
        ["package.toml", "execution.toml", "input-source.toml", "replay.jl"],
        ["run/" * p for p in RUN_FILES],
        R1_SOURCES,
        ["environment/" * replace(p, '\\' => '/') for p in ENV_FILES],
        ["figures/figure-config.toml", "figures/F04-residuals.csv"],
    )
    all(p -> haskey(expected, p), required) || error("Incomplete beginner package")
    package = toml(joinpath(root, "package.toml"))
    execution = toml(joinpath(root, "execution.toml"))
    package["schema"] == "r10-beginner-v1" && package["origin"] == "synthetic" ||
        error("Invalid scope or origin")
    package["source_commit"] == execution["source_commit"] || error("Commit identity mismatch")
    execution["status"] == "passed" && all(s -> s["exitcode"] == 0, execution["steps"]) ||
        error("Execution was not completed")
    # 不将现有depot预检提升为全新主机或主机许可移除后的验收。
    execution["existing_depot_reused"] &&
    !execution["fresh_machine_verified"] &&
    !execution["gurobi_license_removed"] || error("Changed environment scope")
    meta = toml(joinpath(root, "run", "metadata.toml"))
    meta["origin"] == "synthetic" && meta["run_id"] == package["run_id"] || error("Run identity")
    for p in R1_SOURCES
        sha(safe(root, p)) == meta["hashes"][p] || error("Frozen scientific source mismatch")
    end
    for p in ENV_FILES
        key = replace(p, '\\' => '/')
        h = sha(safe(root, "environment/" * key))
        h ==
        execution["environment_hashes_before"][key] ==
        execution["environment_hashes_after"][key] || error("Environment changed")
    end
    sha(joinpath(root, "input-source.toml")) == meta["source_input_sha256"] || error("Source input")
    sha(joinpath(root, "run", "case.toml")) == meta["saved_case_sha256"] || error("Saved input")
    sha(joinpath(root, "run", "solution.toml")) == meta["solution_sha256"] ||
        error("Saved solution")
    frozen = Module(gensym(:FrozenR1))
    Core.eval(frozen, :(using TOML, SHA))
    for p in R1_SOURCES
        Base.include(frozen, safe(root, p))
    end
    loader = Base.invokelatest(getfield, frozen, :load_case)
    validator = Base.invokelatest(getfield, frozen, :validate_r1_solution)
    c = Base.invokelatest(loader, joinpath(root, "input-source.toml"))
    saved_c = Base.invokelatest(loader, joinpath(root, "run", "case.toml"))
    c.data == saved_c.data || error("Source and saved case differ")
    result = toml(joinpath(root, "run", "solution.toml"))
    result["objective"] == execution["objective"] || error("Execution objective mismatch")
    report = Base.invokelatest(validator, c, result)
    report.relaxed_pass && report.original_branch_pass ||
        error("Independent physical replay failed")
    validation = toml(joinpath(root, "run", "validation.toml"))
    validation["relaxed_pass"] == report.relaxed_pass &&
    validation["original_branch_pass"] == report.original_branch_pass ||
        error("Stored acceptance mismatch")
    residual_lines = readlines(joinpath(root, "run", "residuals.csv"))
    residual_lines[1] == "id,t,residual,unit,tolerance,pass" || error("Residual schema")
    length(residual_lines) == length(report.rows) + 1 || error("Residual rows missing")
    for (line, r) in zip(residual_lines[2:end], report.rows)
        x = split(line, ',')
        (
            String(x[1]),
            parse(Int, x[2]),
            parse(Float64, x[3]),
            String(x[4]),
            parse(Float64, x[5]),
            parse(Bool, x[6]),
        ) == Tuple(r) || error("Residual values changed")
    end
    sha(joinpath(root, "run", "residuals.csv")) ==
    sha(joinpath(root, "figures", "F04-residuals.csv")) || error("Figure residual source mismatch")
    figures = toml(joinpath(root, "figures", "figure-config.toml"))
    figures["run_id"] == meta["run_id"] &&
    figures["redraw_only"] &&
    figures["solution_sha256"] == meta["solution_sha256"] &&
    figures["input_sha256"] == meta["source_input_sha256"] || error("Figure identity mismatch")
    for file in ("timeseries.csv", "states.csv")
        sha(joinpath(root, "run", file)) == sha(joinpath(root, "figures", "F03-" * file)) ||
            error("Trajectory figure source mismatch")
    end
    for name in ("F01-topology", "F02-devices", "F03-trajectories", "F04-residuals"),
        ext in ("png", "svg")

        haskey(expected, "figures/" * name * "." * ext) || error("Missing figure")
    end
    Dict(
        "run_id" => meta["run_id"],
        "objective" => result["objective"],
        "residual_rows" => length(report.rows),
        "max_residual_ratio" => maximum(r.residual / r.tolerance for r in report.rows),
        "model_pass" => report.relaxed_pass,
        "original_branch_pass" => report.original_branch_pass,
    )
end

"""
    archive(probe_dir, new_output)

从已完成的隔离预检复制显式白名单中的原件、图源、最小验证源码和环境；拒绝覆盖。
原日志仅保存哈希与退出状态，含本机路径的日志留本地；不复制论文原件或其他运行。
"""
function archive(probe_dir, output)
    ispath(output) && error("Refuse to replace an existing package")
    probe = toml(joinpath(probe_dir, "probe.toml"))
    probe["status"] == "passed" || error("Only completed preflight may be archived")
    clone = abspath(joinpath(probe_dir, probe["clone_relative_to_output"]))
    run = joinpath(clone, "results", "runs", probe["run_id"])
    mkdir(output)
    function copy_file(from, relative)
        to = safe(output, relative)
        mkpath(dirname(to))
        cp(from, to)
    end
    for p in RUN_FILES
        copy_file(joinpath(run, p), "run/" * p)
    end
    for p in R1_SOURCES
        copy_file(joinpath(clone, p), p)
    end
    for p in ENV_FILES
        copy_file(joinpath(clone, p), "environment/" * replace(p, '\\' => '/'))
    end
    for p in readdir(joinpath(probe_dir, "figures"))
        copy_file(joinpath(probe_dir, "figures", p), "figures/" * p)
    end
    copy_file(joinpath(clone, "configs", "r1", "micro.toml"), "input-source.toml")
    copy_file(@__FILE__, "replay.jl")
    execution = deepcopy(probe)
    delete!(execution, "clone_relative_to_output")
    execution["original_probe_sha256"] = sha(joinpath(probe_dir, "probe.toml"))
    execution["logs"] = "Original logs remain local; hashes and exit codes preserved here."
    execution["test_entry"] = "Temporary wrapper includes the existing test/r1.jl (63 assertions)."
    write_toml(joinpath(output, "execution.toml"), execution)
    write_toml(
        joinpath(output, "package.toml"),
        Dict(
            "schema" => "r10-beginner-v1",
            "origin" => "synthetic",
            "scope" => "R1 fixed-flow two-node subset",
            "source_commit" => probe["source_commit"],
            "run_id" => probe["run_id"],
            "claim" => "Clean-checkout beginner preflight with an existing depot; not a fresh-machine or full-thesis acceptance.",
            "visual_review" => "All four PNGs inspected; axes, units, run ID and residual threshold visible.",
        ),
    )
    write(
        joinpath(output, "README.md"),
        """
# R10 入门路径：隔离克隆预检证据

原提交 $(probe["source_commit"])；运行 $(probe["run_id"])，合成R1特例。
无论文原件、无旧运行数据。63项现有R1断言、模型/原支路等式独立验证、
F01–F04重绘和严格文档通过；六环境文件与重绘前后的运行原件保持。
复用现有Julia depot，测试未加载Gurobi，但未移除主机许可，不能称全新主机验收。

用Julia 1.12.6执行 `replay.jl check <本目录>`，仅使用标准库，
从冻结的四个R1源码文件独立重算保存控制量、全部残差、费用及图源身份。
此重验不重新求解，不检查未建模水力、一般动态网络或整篇论文结论。
`execution.toml`保留原执行时间、日志哈希、阶段退出码及环境边界；
含本机路径的原日志仍在本地，未复制到本包。
历史R1失败在r1-first-batch中保留，本包不改判它们。
""",
    )
    sign(output)
    check(output)
end
end

if abspath(PROGRAM_FILE) == @__FILE__
    length(ARGS) in (2, 3) ||
        error("Usage: r10_beginner_evidence.jl check BUNDLE | archive PROBE NEW_OUTPUT")
    if ARGS[1] == "check" && length(ARGS) == 2
        println(R10BeginnerEvidence.check(ARGS[2]))
    elseif ARGS[1] == "archive" && length(ARGS) == 3
        println(R10BeginnerEvidence.archive(ARGS[2], ARGS[3]))
    else
        error("Unknown operation")
    end
end
