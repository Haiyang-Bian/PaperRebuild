module R9FixedStudy
push!(LOAD_PATH, normpath(joinpath(@__DIR__, "..")))
using JuMP, TOML, SHA, Dates, UUIDs, CSV, Random
const ROOT=normpath(joinpath(@__DIR__, ".."))
hashfile(p) = bytes2hex(sha256(read(p)))
toml(p, x) = open(io->TOML.print(io, x; sorted = true), p, "w")

function freeze(parent, out)
    ispath(out) && error("Do not overwrite study")
    previous=TOML.parsefile(joinpath(parent, "manifest.toml"))
    science=[
        previous["science_files"];
        [
            "src/algorithms/r3_sensitivity.jl",
            "src/formulations/r9_terminal.jl",
            "src/verification/r9_fixed.jl",
            "src/reporting/r9_fixed.jl",
        ]
    ]
    files=Dict{String,String}()
    mkpath(out)
    for path in [
        science;
        [
            "Project.toml",
            "Manifest.toml",
            "tools/solvers/Project.toml",
            "tools/solvers/Manifest.toml",
        ]
    ]
        target=joinpath(out, "code", path)
        mkpath(dirname(target))
        cp(joinpath(ROOT, path), target)
        files["code/"*path]=hashfile(target)
    end
    for (source, target) in (
        (joinpath(parent, "case.toml"), "case.toml"),
        (joinpath(parent, "runs/vf_vt/stage.toml"), "vf-vt-parent.toml"),
        (@__FILE__, "study-source.jl"),
    )
        cp(source, joinpath(out, target))
        files[target]=hashfile(joinpath(out, target))
    end
    entries=[
        Dict(
            "id"=>lowercase(terminal*"_"*solver),
            "mode"=>"VF_VT",
            "solver"=>solver,
            "budget_sec"=>600.0,
            "terminal"=>terminal,
            "physical"=>false,
            "flow_source"=>"saved_vf_vt_reference_parameter_only",
        ) for terminal in ("literal", "roundoff_band") for solver in ("Clarabel", "Gurobi")
    ]
    manifest=Dict(
        "schema"=>"r9-fixed-study-v1",
        "files"=>files,
        "science_files"=>science,
        "entries"=>entries,
        "input_sha256"=>files["case.toml"],
        "origin"=>"synthetic",
        "uses_projected_gradient"=>false,
        "initial_primal_injection"=>false,
        "gurobi_presolve"=>0,
        "numerical_interpretation_error_K"=>1e-10,
        "source_manifest_sha256"=>hashfile(joinpath(parent, "manifest.toml")),
        "created_utc"=>string(now(UTC)),
        "julia_version"=>string(VERSION),
    )
    toml(joinpath(out, "manifest.toml"), manifest)
    println("Four fixed-flow subproblems frozen; no optimization.")
end

function load(out)
    meta=TOML.parsefile(joinpath(out, "manifest.toml"))
    meta["schema"]=="r9-fixed-study-v1" || error("Unknown fixed study")
    for (path, hash) in meta["files"]
        isabspath(path) || occursin("..", path) ? error("Unsafe path") : nothing
        hashfile(joinpath(out, path))==hash || error("Frozen file changed: $path")
    end
    mod=Module(gensym(:R9FixedFrozen))
    Core.eval(mod, :(using JuMP, TOML, SHA, Dates, UUIDs, CSV, Random))
    for path in meta["science_files"]
        Base.include(mod, joinpath(out, "code", path))
    end
    c=Base.invokelatest() do
        getfield(mod, :load_r9_pv_case)(joinpath(out, "case.toml"))
    end
    return (; meta, mod, c)
end

function run(out, solver)
    solver in ("Clarabel", "Gurobi") || error("Unknown solver")
    f=load(out)
    Core.eval(@__MODULE__, Expr(:using, Expr(:., Symbol(solver))))
    optimizer=Base.invokelatest() do
        factory=getfield(getfield(@__MODULE__, Symbol(solver)), :Optimizer)
        solver=="Gurobi" ? optimizer_with_attributes(factory, "Presolve"=>0) : factory
    end
    for entry in f.meta["entries"]
        entry["solver"]==solver || continue
        folder=joinpath(out, "runs", entry["id"])
        ispath(folder) && error("Do not overwrite result")
        mkpath(folder)
        start=time_ns()/1e9
        flow=entry["mode"]=="CF_VT" ? nothing :
             TOML.parsefile(joinpath(out, "vf-vt-parent.toml"))["values"]["m_pipe"]
        result=try
            Base.invokelatest() do
                m=getfield(f.mod, :r2_flow_matrix)(f.c, flow)
                getfield(f.mod, :solve_r9_fixed_case)(
                    f.c,
                    m;
                    mode = Symbol(entry["mode"]),
                    terminal = Symbol(entry["terminal"]),
                    optimizer,
                    budget_sec = entry["budget_sec"],
                )
            end
        catch err
            Dict{String,Any}("status"=>"exception", "error"=>sprint(showerror, err))
        end
        toml(joinpath(folder, "result.toml"), result)
        toml(
            joinpath(folder, "receipt.toml"),
            Dict(
                "entry"=>entry,
                "wall_sec"=>time_ns()/1e9-start,
                "result_sha256"=>hashfile(joinpath(folder, "result.toml")),
            ),
        )
        println(
            entry["id"],
            " ",
            get(result, "status", "missing"),
            " ",
            get(result, "validation", Dict()),
            " KKT=",
            get(get(result, "kkt", Dict()), "trusted", false),
        )
        flush(stdout)
    end
    all(hashfile(joinpath(out, p))==h for (p, h) in f.meta["files"]) || error("Source changed")
end

function check(study, report)
    ispath(report) && error("Do not overwrite report")
    f=load(study)
    mkpath(report)
    cp(@__FILE__, joinpath(report, "report-source.jl"))
    rows=NamedTuple[]
    for e in f.meta["entries"]
        folder=joinpath(study, "runs", e["id"])
        receipt=TOML.parsefile(joinpath(folder, "receipt.toml"))
        hashfile(joinpath(folder, "result.toml"))==receipt["result_sha256"] ||
            error("Result changed")
        r=TOML.parsefile(joinpath(folder, "result.toml"))
        if r["status"]=="exception"
            push!(
                rows,
                (;
                    id = e["id"],
                    status = r["status"],
                    model_pass = false,
                    physical_pass = false,
                    terminal_pass = false,
                    energy_pass = false,
                    kkt_trusted = false,
                    cost_CNY = NaN,
                    bound_CNY = NaN,
                    relative_gap = NaN,
                    elapsed_sec = receipt["wall_sec"],
                    budget_pass = receipt["wall_sec"]<=600,
                ),
            )
            continue
        end
        v=Base.invokelatest() do
            getfield(f.mod, :validate_r9_fixed_solution)(f.c, r)
        end
        CSV.write(joinpath(report, e["id"]*"-residuals.csv"), v.rows; newline = '\n')
        s, k=r["stage"], r["kkt"]
        push!(
            rows,
            (;
                id = e["id"],
                status = r["status"],
                model_pass = v.model_pass,
                physical_pass = v.physical_pass,
                terminal_pass = v.terminal_pass,
                energy_pass = v.daily_energy_pass,
                kkt_trusted = k["trusted"],
                cost_CNY = get(s, "operating_cost", NaN),
                bound_CNY = get(s, "solver_bound", NaN),
                relative_gap = get(s, "solver_relative_gap", NaN),
                elapsed_sec = receipt["wall_sec"],
                budget_pass = r["wall_budget_pass"]&&receipt["wall_sec"]<=600,
            ),
        )
    end
    CSV.write(joinpath(report, "summary.csv"), rows; newline = '\n')
    toml(
        joinpath(report, "manifest.toml"),
        Dict(
            "schema"=>"r9-fixed-report-v1",
            "study_manifest_sha256"=>hashfile(joinpath(study, "manifest.toml")),
            "files"=>Dict(p=>hashfile(joinpath(report, p)) for p in readdir(report)),
        ),
    )
    foreach(println, rows)
end

function main(args)
    length(args)==3 || error(
        "usage: r9_fixed_study.jl freeze PARENT NEW_STUDY | run STUDY Clarabel|Gurobi | check STUDY NEW_REPORT",
    )
    action, a, b=args
    action=="freeze" ? freeze(abspath(a), abspath(b)) :
    action=="run" ? run(abspath(a), b) :
    action=="check" ? check(abspath(a), abspath(b)) : error("Unknown action")
end
end
if abspath(PROGRAM_FILE) == abspath(@__FILE__)
    R9FixedStudy.main(ARGS)
end
