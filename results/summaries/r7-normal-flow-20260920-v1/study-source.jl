using PaperRebuild, JuMP, TOML, SHA, Dates
const FLOW_ROOT=normpath(joinpath(@__DIR__, ".."))
const FLOW_MODULES=Dict{String,Module}()

function flow_manifest(dir)
    Dict(
        replace(relpath(joinpath(p, f), dir), '\\'=>'/')=>bytes2hex(sha256(read(joinpath(p, f))))
        for (p, _, fs) in walkdir(dir) for f in fs
    )
end
function flow_capture(cmd)
    mktempdir(joinpath(FLOW_ROOT, "tmp")) do dir
        out=joinpath(dir, "out")
        err=joinpath(dir, "err")
        run(pipeline(cmd; stdin = devnull, stdout = out, stderr = err))
        read(out, String)
    end
end
function flow_rule_spec(c, rule, control)
    h=c.data["heat"]
    T=c.data["periods"]
    arrays=Dict(
        "pipe"=>reduce(vcat, permutedims(p["normal_flow_kg_s"]) for p in h["pipes"]),
        "source"=>reduce(vcat, permutedims.(h["source_flow_kg_s"])),
        "load"=>reduce(vcat, permutedims.(h["load_flow_kg_s"])),
    )
    lo=deepcopy(arrays)
    hi=deepcopy(arrays)
    if control=="continuous"
        for kind in ("pipe", "source", "load")
            caps=kind=="pipe" ? [p["flow_max_kg_s"] for p in h["pipes"]] : h[kind*"_flow_max"]
            for I in CartesianIndices(arrays[kind])
                lo[kind][I]=arrays[kind][I]>0 ? rule["positive_floor_kg_s"] : 0
                hi[kind][I]=arrays[kind][I]>0 ? caps[I[1]] : 0
            end
        end
    elseif control!="prescribed"
        error("流量对照规则错误")
    end
    r7_normal_flow_spec(
        c;
        pipe_min = lo["pipe"],
        pipe_max = hi["pipe"],
        source_min = lo["source"],
        source_max = hi["source"],
        load_min = lo["load"],
        load_max = hi["load"],
    )
end
function flow_freeze(dest)
    ispath(dest)&&error("不覆盖流量实验冻结目录")
    rule=TOML.parsefile(joinpath(FLOW_ROOT, "configs/r7/normal-flow-study.toml"))
    records=Dict{String,Any}[]
    for group in rule["groups"]
        d=TOML.parsefile(
            joinpath(FLOW_ROOT, rule[group=="reserve" ? "normal_reserve" : "normal_hand"]),
        )
        if group=="varying_prices"
            d["name"]*="_varying_prices_v1"
            d["electric"]["price_USD_MWh"]=rule["varying_prices_USD_MWh"]
        end
        c=R7NormalCase(d)
        for control in rule["controls"],
            solver in (control=="prescribed" ? ["HiGHS", "Gurobi"] : ["Gurobi"])

            s=flow_rule_spec(c, rule, control)
            push!(
                records,
                Dict(
                    "id"=>"$(group)_$(control)_$(lowercase(solver))",
                    "group"=>group,
                    "control"=>control,
                    "solver"=>solver,
                    "case"=>c.data,
                    "spec"=>s,
                    "case_sha256"=>c.sha256,
                    "spec_sha256"=>PaperRebuild.r7_digest(s),
                ),
            )
        end
    end
    length(records)==rule["record_count"] || error("流量冻结数量错误")
    mkpath(dest)
    write(joinpath(dest, "inputs.toml"), PaperRebuild.r7_text(Dict("records"=>records)))
    write(joinpath(dest, "rule.toml"), PaperRebuild.r7_text(rule))
    write(
        joinpath(dest, "environment.toml"),
        PaperRebuild.r7_text(
            Dict(
                "origin"=>"synthetic",
                "utc"=>string(now(UTC)),
                "julia_version"=>string(VERSION),
                "seed"=>"deterministic_no_sampling",
                "git_head"=>strip(flow_capture(`git -C $FLOW_ROOT rev-parse HEAD`)),
                "git_status"=>flow_capture(`git -C $FLOW_ROOT status --porcelain`),
            ),
        ),
    )
    cp(@__FILE__, joinpath(dest, "study-source.jl"))
    for (p, f) in PaperRebuild.r7_normal_flow_science_paths()
        target=joinpath(dest, "code", split(p, '/')...)
        mkpath(dirname(target))
        cp(f, target)
    end
    write(
        joinpath(dest, "freeze.toml"),
        PaperRebuild.r7_text(
            Dict(
                "files"=>flow_manifest(dest),
                "science"=>PaperRebuild.r7_normal_flow_science_hashes(),
            ),
        ),
    )
    println("9 inputs and continuous-flow rules frozen before formal optimization.")
end
function flow_inputs(dir; current = false)
    f=TOML.parsefile(joinpath(dir, "freeze.toml"))
    for (p, h) in f["files"]
        !isabspath(p)&&!occursin(':', p)&&!occursin('\\', p)&&all(
            x->!(x in ("", ".", "..")),
            split(p, '/'),
        ) || error("冻结路径错误")
        bytes2hex(sha256(read(joinpath(dir, split(p, '/')...))))==h || error("流量预冻结内容已改变")
    end
    current &&
        f["science"]!=PaperRebuild.r7_normal_flow_science_hashes() &&
        error("流量源码与预冻结不同")
    current &&
        read(@__FILE__)!=read(joinpath(dir, "study-source.jl")) &&
        error("流量编排与预冻结不同")
    TOML.parsefile(joinpath(dir, "inputs.toml"))["records"],
    TOML.parsefile(joinpath(dir, "rule.toml"))
end
function flow_optimizer(solver)
    if solver=="Gurobi"
        return optimizer_with_attributes(
            Gurobi.Optimizer,
            "Threads"=>1,
            "NonConvex"=>2,
            "FeasibilityTol"=>1e-9,
            "OptimalityTol"=>1e-9,
            "IntFeasTol"=>1e-9,
            "MIPGap"=>1e-8,
            "DualReductions"=>0,
        )
    end
    optimizer_with_attributes(
        HiGHS.Optimizer,
        "threads"=>1,
        "primal_feasibility_tolerance"=>1e-9,
        "dual_feasibility_tolerance"=>1e-9,
        "mip_feasibility_tolerance"=>1e-9,
        "mip_rel_gap"=>1e-8,
    )
end
function flow_run(dir, solver)
    items, rule=flow_inputs(dir; current = true)
    todo=filter(x->x["solver"]==solver, items)
    isempty(todo)&&error("未声明的求解器组")
    any(ispath(joinpath(dir, "records", x["id"])) for x in todo)&&error(
        "该运行组已开始，不覆盖或重开",
    )
    opt=flow_optimizer(solver)
    for x in todo
        println("Starting ", x["id"])
        flush(stdout)
        c=R7NormalCase(x["case"])
        s=x["spec"]
        r=solve_r7_normal_flow(c, s; optimizer = opt, budget_sec = rule["budget_sec"])
        save_r7_normal_flow(c, s, r, joinpath(dir, "records", x["id"]))
        println(
            x["id"],
            " ",
            r["status"],
            " pass=",
            r["candidate_accepted"],
            " cost=",
            get(r, "solver_objective_USD", "missing"),
        )
        flush(stdout)
    end
end
function flow_read(dir)
    key=PaperRebuild.r7_digest(
        TOML.parsefile(joinpath(dir, "result.toml"))["source_hashes_at_solve"],
    )
    if !haskey(FLOW_MODULES, key)
        mod=Module(gensym(:FrozenFlow))
        Base.include(mod, abspath(joinpath(dir, "code/replay.jl")))
        FLOW_MODULES[key]=Base.invokelatest(getfield, mod, :FrozenR7NormalFlow)
        return Base.invokelatest(getfield, mod, :x)
    end
    Base.invokelatest(Base.invokelatest(getfield, FLOW_MODULES[key], :read_r7_normal_flow), dir)
end
function flow_csv(path, headers, rows)
    open(path, "w") do io
        println(io, join(headers, ','))
        for row in rows
            println(io, join(("\""*replace(string(v), '"'=>"\"\"")*"\"" for v in row), ','))
        end
    end
end
function flow_report(dir, dest)
    ispath(dest)&&error("不覆盖流量实验报告")
    items, rule=flow_inputs(dir)
    all(ispath(joinpath(dir, "records", x["id"])) for x in items) || error("正式运行不完整")
    # 原值和冻结源码完整复制，后续报告不调用任何优化器。
    cp(dir, dest)
    rows=Vector{Any}[]
    trajectories=Vector{Any}[]
    for x in items
        a=flow_read(joinpath(dest, "records", x["id"]))
        r=a.result
        v=a.validation
        push!(
            rows,
            [
                x["id"],
                x["group"],
                x["control"],
                x["solver"],
                r["run_id"],
                r["status"],
                r["candidate_accepted"],
                r["domain_cost_complete"],
                get(v, "cost_USD", ""),
                get(r, "lower_bound_USD", ""),
                r["elapsed_sec"],
            ],
        )
        if r["candidate_accepted"]
            f=PaperRebuild.r7_unpack(r["flow_values"], "pipe")
            for pipe in axes(f, 1), t in axes(f, 2), w in 1:length(a.case.data["probabilities"])
                push!(
                    trajectories,
                    [
                        x["id"],
                        r["run_id"],
                        x["group"],
                        x["control"],
                        x["solver"],
                        pipe,
                        t,
                        w,
                        f[pipe, t],
                        PaperRebuild.r7_unpack(r["values"], "τ_pipe_S")[pipe, t, w],
                        PaperRebuild.r7_unpack(r["values"], "τ_pipe_R")[pipe, t, w],
                        PaperRebuild.r7_unpack(r["values"], "E_pipe_S")[pipe, t+1, w],
                        PaperRebuild.r7_unpack(r["values"], "E_pipe_R")[pipe, t+1, w],
                    ],
                )
            end
        end
    end
    flow_csv(
        joinpath(dest, "summary.csv"),
        [
            "record",
            "group",
            "control",
            "solver",
            "run_id",
            "status",
            "model_pass",
            "cost_complete",
            "cost_USD",
            "lower_bound_USD",
            "elapsed_sec",
        ],
        rows,
    )
    flow_csv(
        joinpath(dest, "trajectories.csv"),
        [
            "record",
            "run_id",
            "group",
            "control",
            "solver",
            "pipe",
            "time_h",
            "scenario",
            "flow_kg_s",
            "outlet_S_K",
            "outlet_R_K",
            "inventory_S_MWh",
            "inventory_R_MWh",
        ],
        trajectories,
    )
    write(
        joinpath(dest, "report-hashes.toml"),
        PaperRebuild.r7_text(Dict("files"=>flow_manifest(dest))),
    )
    println("9 frozen normal-flow records independently replayed; no optimization in report.")
end
function flow_check(dir)
    flow_inputs(dir)
    hashes=TOML.parsefile(joinpath(dir, "report-hashes.toml"))["files"]
    for (p, h) in hashes
        !isabspath(p)&&!occursin(':', p)&&!occursin('\\', p)&&all(
            x->!(x in ("", ".", "..")),
            split(p, '/'),
        ) || error("报告路径错误")
        bytes2hex(sha256(read(joinpath(dir, split(p, '/')...))))==h || error("报告篡改")
    end
    items, _=flow_inputs(dir)
    for x in items
        a=flow_read(joinpath(dir, "records", x["id"]))
        a.case.sha256==x["case_sha256"] && PaperRebuild.r7_digest(a.spec)==x["spec_sha256"] ||
            error("运行未使用冻结输入")
    end
    println("9 source-frozen flow records checked.")
end
if abspath(PROGRAM_FILE)==@__FILE__
    length(ARGS)>=2 ||
        error("usage: r7_normal_flow_study.jl freeze|run|report|check DIR [SOLVER|DEST]")
    action=ARGS[1]
    dir=abspath(ARGS[2])
    if action=="run"
        ARGS[3]=="Gurobi" ? (@eval using Gurobi) : (@eval using HiGHS)
    end
    action=="freeze" ? flow_freeze(dir) :
    action=="run" ? flow_run(dir, ARGS[3]) :
    action=="report" ? flow_report(dir, abspath(ARGS[3])) :
    action=="check" ? flow_check(dir) : error("unknown action")
end
