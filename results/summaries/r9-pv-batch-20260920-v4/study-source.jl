module R9PVStudy
using PaperRebuild, TOML, CSV, SHA, Dates

const ROOT = normpath(joinpath(@__DIR__, ".."))
const CODE = [
    "src/"*p for p in (
        "components/devices.jl",
        "networks/fixed_flow_heat.jl",
        "core/case.jl",
        "formulations/r1.jl",
        "verification/r1.jl",
        "reporting/runs.jl",
        "networks/water_mass.jl",
        "core/r2_case.jl",
        "core/r3_operation.jl",
        "formulations/r2.jl",
        "reporting/r2_runs.jl",
        "verification/r2.jl",
        "core/r3.jl",
        "formulations/r3.jl",
        "verification/r3.jl",
        "reporting/r3_runs.jl",
        "reporting/r3_modes.jl",
        "core/r9_inputs.jl",
        "verification/r9_sources.jl",
        "core/r9_pv.jl",
        "verification/r9_pv.jl",
        "formulations/r9_pv.jl",
        "reporting/r9_pv.jl",
    )
]
hashfile(p) = bytes2hex(sha256(read(p)))
textfile(d) = PaperRebuild.r9_text(d)

function freeze(out)
    ispath(out) && error("不覆盖冻结批次")
    protocol = joinpath(ROOT, "configs/r9/pv-protocol.toml")
    c = r9_pv_case(joinpath(ROOT, "docs/reading/ch07"), protocol)
    audit = audit_r9_pv_input(c)
    audit.pass || error("预优化输入失败")
    mkpath(out)
    files = Dict{String,String}()
    for path in [
        CODE;
        "Project.toml";
        "Manifest.toml";
        "tools/solvers/Project.toml";
        "tools/solvers/Manifest.toml"
    ]
        target = joinpath(out, "code", path)
        mkpath(dirname(target))
        cp(joinpath(ROOT, path), target)
        files["code/"*path] = hashfile(target)
    end
    for name in ("inputs.toml", "topology.toml", "reported-results.toml")
        cp(joinpath(ROOT, "docs/reading/ch07", name), joinpath(out, "source-"*name))
        files["source-"*name] = hashfile(joinpath(out, "source-"*name))
    end
    cp(protocol, joinpath(out, "protocol.toml"))
    write(joinpath(out, "case.toml"), textfile(c.data))
    CSV.write(joinpath(out, "input-checks.csv"), audit.rows)
    cp(@__FILE__, joinpath(out, "study-source.jl"))
    for path in ("protocol.toml", "case.toml", "input-checks.csv", "study-source.jl")
        files[path] = hashfile(joinpath(out, path))
    end
    entries = [
        Dict(
            "id"=>lowercase(mode)*"_"*lowercase(solver)*(physical ? "_original" : "_socp"),
            "mode"=>mode,
            "solver"=>solver,
            "physical"=>physical,
            "budget_sec"=>600.0,
        ) for mode in ("CF_CT", "CF_VT"),
        (solver, physical) in (("Clarabel", false), ("Gurobi", false), ("Gurobi", true))
    ]
    manifest = Dict(
        "schema"=>"r9-pv-study-v1",
        "created_utc"=>string(now(UTC)),
        "input_sha256"=>c.sha256,
        "origin"=>"synthetic",
        "julia_version"=>string(VERSION),
        "science_files"=>CODE,
        "files"=>files,
        "entries"=>vec(entries),
    )
    write(joinpath(out, "manifest.toml"), textfile(manifest))
    return manifest
end

function frozen(out)
    out=abspath(out)
    manifest = TOML.parsefile(joinpath(out, "manifest.toml"))
    manifest["schema"] == "r9-pv-study-v1" || error("批次身份错误")
    Set(manifest["science_files"]) == Set(CODE) || error("冻结源码清单改变")
    for (path, hash) in manifest["files"]
        isabspath(path) || occursin("..", path) ? error("非法证据路径") : nothing
        hashfile(joinpath(out, path)) == hash || error("冻结文件已改变：$path")
    end
    mod = Module(gensym(:R9PVFrozen))
    Core.eval(mod, :(using JuMP, TOML, SHA, Dates, UUIDs, CSV, Random))
    for path in manifest["science_files"]
        Base.include(mod, joinpath(out, "code", path))
    end
    c = Base.invokelatest(() -> getfield(mod, :load_r9_pv_case)(joinpath(out, "case.toml")))
    c.sha256 == manifest["input_sha256"] || error("输入哈希不符")
    return (; manifest, mod, c)
end

function optimizer_factory(solver)
    solver in ("Clarabel", "Gurobi") || error("求解器未登记")
    package = Symbol(solver)
    Core.eval(Main, Expr(:using, Expr(:., package)))
    return Base.invokelatest(() -> getfield(getfield(Main, package), :Optimizer))
end

function run(out, solver)
    f = frozen(out)
    optimizer = optimizer_factory(solver)
    for entry in f.manifest["entries"]
        entry["solver"] == solver || continue
        dir = joinpath(out, "runs", entry["id"])
        ispath(dir) && error("不重跑或覆盖已存在运行：$dir")
        mkpath(dir)
        write(
            joinpath(dir, "started.toml"),
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
                () -> getfield(f.mod, :solve_r9_pv_case)(
                    f.c;
                    mode = Symbol(entry["mode"]),
                    physical = entry["physical"],
                    optimizer,
                    budget_sec = entry["budget_sec"],
                ),
            )
        catch err
            write(joinpath(dir, "failure.txt"), sprint(showerror, err, catch_backtrace()))
            rethrow()
        end
        write(joinpath(dir, "result.toml"), textfile(r))
        v = Base.invokelatest(() -> getfield(f.mod, :validate_r9_pv_solution)(f.c, r))
        files = Dict(
            "result.toml"=>hashfile(joinpath(dir, "result.toml")),
            "started.toml"=>hashfile(joinpath(dir, "started.toml")),
        )
        for (i, rows) in enumerate(Iterators.partition(v.rows, 8000))
            name = "residuals-"*lpad(i, 3, '0')*".csv"
            CSV.write(joinpath(dir, name), collect(rows))
            files[name] = hashfile(joinpath(dir, name))
        end
        write(
            joinpath(dir, "evidence.toml"),
            textfile(
                Dict(
                    "schema"=>"r9-pv-evidence-v1",
                    "files"=>files,
                    "residual_count"=>length(v.rows),
                    "model_pass"=>v.model_pass,
                    "physical_pass"=>v.physical_pass,
                    "terminal_pass"=>v.terminal_pass,
                ),
            ),
        )
        println(
            entry["id"],
            ": ",
            r["status"],
            "; model=",
            v.model_pass,
            "; physical=",
            v.physical_pass,
            "; elapsed=",
            round(r["elapsed_sec"]; digits = 2),
        )
        flush(stdout)
    end
end

function report(out, target)
    ispath(target) && error("不覆盖报告")
    f = frozen(out)
    rows, traces, residuals = NamedTuple[], NamedTuple[], NamedTuple[]
    for entry in f.manifest["entries"]
        dir = joinpath(out, "runs", entry["id"])
        evidence = TOML.parsefile(joinpath(dir, "evidence.toml"))
        for (path, hash) in evidence["files"]
            hashfile(joinpath(dir, path)) == hash || error("运行文件已改变")
        end
        r = TOML.parsefile(joinpath(dir, "result.toml"))
        v = Base.invokelatest(() -> getfield(f.mod, :validate_r9_pv_solution)(f.c, r))
        length(v.rows) == evidence["residual_count"] || error("残差数量改变")
        all(
            evidence[string(k)] == getproperty(v, k) for
            k in (:model_pass, :physical_pass, :terminal_pass)
        ) || error("重验判定改变")
        saved = reduce(
            vcat,
            [
                collect(CSV.File(joinpath(dir, p))) for
                p in sort(collect(keys(evidence["files"]))) if startswith(p, "residuals-")
            ];
            init = Any[],
        )
        length(saved) == length(v.rows) || error("残差文件不完整")
        for (a, b) in zip(saved, v.rows), k in keys(b)
            isequal(getproperty(a, k), getproperty(b, k)) || error("残差原值回放不一致")
        end
        stage = r["stage"]
        pv = findall(g -> g["kind"] == "PV", f.c.data["devices"])
        available = sum(sum(f.c.data["devices"][g]["availability"]) for g in pv)*f.c.data["dt_h"]
        used =
            haskey(stage, "values") ?
            sum(sum(stage["values"]["P_device"][g]) for g in pv)*f.c.data["dt_h"] : missing
        push!(
            rows,
            (
                id = entry["id"],
                mode = entry["mode"],
                solver = entry["solver"],
                physical_model = entry["physical"],
                status = r["status"],
                model_pass = v.model_pass,
                physical_pass = v.physical_pass,
                terminal_pass = v.terminal_pass,
                cost_CNY = get(stage, "operating_cost", missing),
                bound_CNY = get(stage, "solver_bound", missing),
                gap = get(stage, "solver_relative_gap", missing),
                pv_available_MWh = available,
                pv_used_MWh = used,
                elapsed_sec = r["elapsed_sec"],
                wall_budget_pass = r["wall_budget_pass"],
            ),
        )
        for x in v.rows
            push!(residuals, (run_id = entry["id"], x...))
        end
        if haskey(stage, "values")
            val = stage["values"]
            for t in 1:f.c.data["T"]
                push!(
                    traces,
                    (
                        run_id = entry["id"],
                        t,
                        grid_MW = val["P_grid"][t],
                        heat_load_MW = sum(n["H_MW"][t] for n in f.c.data["heat"]["nodes"]),
                        heat_source_MW = sum(val["H_port"][j][t] for j in (1, 15)),
                        source1_K = val["tau_S_port"][1][t],
                        source15_K = val["tau_S_port"][15][t],
                        pv_available_MW = sum(
                            f.c.data["devices"][g]["availability"][t] for g in pv
                        ),
                        pv_used_MW = sum(val["P_device"][g][t] for g in pv),
                    ),
                )
            end
        end
    end
    mkpath(target)
    CSV.write(joinpath(target, "summary.csv"), rows)
    CSV.write(joinpath(target, "trajectories.csv"), traces)
    names = ["summary.csv", "trajectories.csv"]
    for (i, part) in enumerate(Iterators.partition(residuals, 8000))
        name = "residuals-"*lpad(i, 3, '0')*".csv"
        CSV.write(joinpath(target, name), collect(part))
        push!(names, name)
    end
    write(
        joinpath(target, "report.toml"),
        textfile(
            Dict(
                "schema"=>"r9-pv-report-v1",
                "batch_manifest_sha256"=>hashfile(joinpath(out, "manifest.toml")),
                "source_batch"=>replace(relpath(out, ROOT), '\\'=>'/'),
                "origin"=>"synthetic",
                "run_count"=>length(rows),
                "residual_count"=>length(residuals),
                "files"=>Dict(name=>hashfile(joinpath(target, name)) for name in names),
            ),
        ),
    )
    return rows
end
end

if abspath(PROGRAM_FILE) == @__FILE__
    length(ARGS)>=2 ||
        error("usage: r9_pv_study.jl freeze DIR | run DIR Clarabel|Gurobi | report DIR NEW_REPORT")
    command, dir = ARGS[1:2]
    if command == "freeze" && length(ARGS)==2
        R9PVStudy.freeze(dir)
    elseif command == "run" && length(ARGS)==3
        R9PVStudy.run(dir, ARGS[3])
    elseif command == "report" && length(ARGS)==3
        R9PVStudy.report(dir, ARGS[3])
    else
        error("未知命令")
    end
end
