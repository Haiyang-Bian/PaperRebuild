module R9NumericsStudy
using JuMP, TOML, CSV, SHA, Dates
include("r9_pv_study.jl")
const BASE = R9PVStudy
const EXTRA = [
    "src/formulations/r9_reduced.jl",
    "src/reporting/r9_reduced.jl",
    "src/verification/r9_reduced.jl",
]
const CODE = [BASE.CODE; EXTRA]
hashfile = BASE.hashfile
textfile = BASE.textfile

function freeze(parent, out)
    p = BASE.frozen(parent)
    m = BASE.freeze(out)
    m["input_sha256"] == p.manifest["input_sha256"] || error("输入相对父批次改变")
    for path in EXTRA
        target = joinpath(out, "code", path)
        mkpath(dirname(target))
        cp(joinpath(BASE.ROOT, path), target)
        m["files"]["code/"*path] = hashfile(target)
    end
    cp(@__FILE__, joinpath(out, "numerics-study-source.jl"))
    m["files"]["numerics-study-source.jl"] = hashfile(joinpath(out, "numerics-study-source.jl"))
    cp(joinpath(@__DIR__, "r9_pv_study.jl"), joinpath(out, "r9_pv_study.jl"))
    m["files"]["r9_pv_study.jl"] = hashfile(joinpath(out, "r9_pv_study.jl"))
    m["schema"] = "r9-numerics-study-v1"
    m["science_files"] = CODE
    m["parent_batch"] = basename(abspath(parent))
    m["parent_manifest_sha256"] = hashfile(joinpath(parent, "manifest.toml"))
    m["terminal_interpretation"] = "reference_anchored"
    m["anchor_shift_limit_K"] = 1e-10
    m["basis_error_limit_K"] = 1e-10
    write(joinpath(out, "manifest.toml"), textfile(m))
    return m
end

function frozen(out)
    out = abspath(out)
    m = TOML.parsefile(joinpath(out, "manifest.toml"))
    m["schema"] == "r9-numerics-study-v1" && Set(m["science_files"]) == Set(CODE) ||
        error("冻结身份错误")
    for (path, hash) in m["files"]
        isabspath(path) || occursin("..", path) ? error("非法相对路径") : nothing
        hashfile(joinpath(out, path)) == hash || error("冻结文件改变：$path")
    end
    mod = Module(gensym(:R9NumericsFrozen))
    Core.eval(mod, :(using JuMP, TOML, SHA, Dates, UUIDs, CSV, Random))
    for path in m["science_files"]
        Base.include(mod, joinpath(out, "code", path))
    end
    c = Base.invokelatest(() -> getfield(mod, :load_r9_pv_case)(joinpath(out, "case.toml")))
    c.sha256 == m["input_sha256"] || error("输入哈希不符")
    return (; manifest = m, mod, c)
end

function run(out, solver)
    f = frozen(out)
    optimizer = BASE.optimizer_factory(solver)
    for entry in f.manifest["entries"]
        entry["solver"] == solver || continue
        target = joinpath(out, "runs", entry["id"])
        ispath(target) && error("不覆盖运行")
        mkpath(target)
        write(
            joinpath(target, "started.toml"),
            textfile(
                Dict(
                    "entry"=>entry,
                    "started_utc"=>string(now(UTC)),
                    "manifest_sha256"=>hashfile(joinpath(out, "manifest.toml")),
                ),
            ),
        )
        r = try
            Base.invokelatest(
                () -> getfield(f.mod, :solve_r9_reduced_case)(
                    f.c;
                    mode = Symbol(entry["mode"]),
                    physical = entry["physical"],
                    optimizer,
                    budget_sec = entry["budget_sec"],
                    terminal = :reference_anchored,
                ),
            )
        catch err
            write(joinpath(target, "failure.txt"), sprint(showerror, err, catch_backtrace()))
            rethrow()
        end
        write(joinpath(target, "result.toml"), textfile(r))
        write(
            joinpath(target, "evidence.toml"),
            textfile(
                Dict(
                    "result_sha256"=>hashfile(joinpath(target, "result.toml")),
                    "started_sha256"=>hashfile(joinpath(target, "started.toml")),
                    "schema"=>"r9-numerics-evidence-v1",
                ),
            ),
        )
        println(
            entry["id"],
            ": ",
            r["status"],
            " ",
            r["validation"],
            " cost=",
            get(r["stage"], "operating_cost", "missing"),
        )
        flush(stdout)
    end
end

function report(batch, out)
    ispath(out) && error("不覆盖报告")
    f = frozen(batch)
    mkpath(out)
    summary, traces, residuals = NamedTuple[], NamedTuple[], NamedTuple[]
    for entry in f.manifest["entries"]
        folder = joinpath(batch, "runs", entry["id"])
        evidence = TOML.parsefile(joinpath(folder, "evidence.toml"))
        evidence["result_sha256"] == hashfile(joinpath(folder, "result.toml")) ||
            error("原值被修改")
        evidence["started_sha256"] == hashfile(joinpath(folder, "started.toml")) ||
            error("运行契约被修改")
        r = TOML.parsefile(joinpath(folder, "result.toml"))
        v = Base.invokelatest(() -> getfield(f.mod, :validate_r9_reduced_solution)(f.c, r))
        s = r["stage"]
        energy =
            haskey(s, "values") ?
            Base.invokelatest(() -> getfield(f.mod, :r9_daily_heat_balance)(f.c, s["values"])) :
            nothing
        push!(
            summary,
            (
                run_id = entry["id"],
                mode = entry["mode"],
                solver = entry["solver"],
                physical_model = entry["physical"],
                status = r["status"],
                termination = get(s, "termination", "missing"),
                cost_CNY = get(s, "operating_cost", missing),
                bound_CNY = get(s, "solver_bound", missing),
                relative_gap = get(s, "solver_relative_gap", missing),
                model_pass = v.model_pass,
                physical_pass = v.physical_pass,
                terminal_pass = v.terminal_pass,
                adopted_terminal_pass = v.adopted_terminal_pass,
                daily_energy_pass = v.daily_energy_pass,
                energy_residual_MWh = isnothing(energy) ? missing : energy.residual_MWh,
                elapsed_sec = r["elapsed_sec"],
                wall_budget_pass = r["wall_budget_pass"],
            ),
        )
        append!(residuals, [merge((run_id = entry["id"],), row) for row in v.rows])
        if haskey(s, "values")
            x = s["values"]
            for t in 1:f.c.data["T"]
                push!(
                    traces,
                    (
                        run_id = entry["id"],
                        t,
                        grid_MW = x["P_grid"][t],
                        source_heat_MW = sum(
                            x["H_port"][j][t] for
                            (j, n) in enumerate(f.c.data["heat"]["nodes"]) if n["role"]=="source"
                        ),
                        pv_MW = sum(
                            x["P_device"][g][t] for
                            (g, d) in enumerate(f.c.data["devices"]) if d["kind"]=="PV"
                        ),
                        source_1_K = x["tau_S_port"][1][t],
                        source_15_K = x["tau_S_port"][15][t],
                    ),
                )
            end
        end
    end
    CSV.write(joinpath(out, "summary.csv"), summary)
    CSV.write(joinpath(out, "trajectories.csv"), traces)
    files =
        Dict(name=>hashfile(joinpath(out, name)) for name in ("summary.csv", "trajectories.csv"))
    for (i, rows) in enumerate(Iterators.partition(residuals, 8000))
        name = "residuals-"*lpad(i, 3, '0')*".csv"
        CSV.write(joinpath(out, name), collect(rows))
        files[name] = hashfile(joinpath(out, name))
    end
    cp(@__FILE__, joinpath(out, "report-source.jl"))
    files["report-source.jl"] = hashfile(joinpath(out, "report-source.jl"))
    write(
        joinpath(out, "report.toml"),
        textfile(
            Dict(
                "schema"=>"r9-numerics-report-v1",
                "source_batch"=>basename(abspath(batch)),
                "manifest_sha256"=>hashfile(joinpath(batch, "manifest.toml")),
                "input_sha256"=>f.c.sha256,
                "residual_count"=>length(residuals),
                "files"=>files,
            ),
        ),
    )
    return summary
end
end

if abspath(PROGRAM_FILE) == @__FILE__
    length(ARGS) == 3 || error(
        "usage: r9_numerics_study.jl freeze PARENT NEW_BATCH | run BATCH Clarabel|Gurobi | report BATCH NEW_REPORT",
    )
    ARGS[1] == "freeze" ? R9NumericsStudy.freeze(ARGS[2:3]...) :
    ARGS[1] == "run" ? R9NumericsStudy.run(ARGS[2:3]...) :
    ARGS[1] == "report" ? R9NumericsStudy.report(ARGS[2:3]...) : error("未知操作")
end
