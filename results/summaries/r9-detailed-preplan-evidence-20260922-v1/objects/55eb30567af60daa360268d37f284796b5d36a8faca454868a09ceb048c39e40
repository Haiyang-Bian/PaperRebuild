# 输入/代码先冻结，三种方法各自一个共享600秒进程；不存在隐式重试。
module R9PreplanStudy
const STARTED=time()
using PaperRebuild, JuMP, TOML, SHA, Dates, UUIDs
const PR=PaperRebuild
const ROOT=dirname(@__DIR__)
module PreviousInput
include("r9_resilience_study.jl")
end

function science()
    merge(
        PR.r9_preplan_science_paths(),
        PR.r7_transport_science_paths(),
        Dict(
            p=>joinpath(ROOT, p) for
            p in ("scripts/r9_preplan_study.jl", "scripts/r9_resilience_study.jl")
        ),
    )
end
safe(p) =
    !isabspath(p)&&!occursin(':', p)&&!occursin('\\', p)&&all(
        x->!(x in ("", ".", "..")),
        split(p, '/'),
    )
hashfile(p) = bytes2hex(sha256(read(p)))
function filehashes(folder)
    Dict(
        replace(relpath(joinpath(d, f), folder), '\\'=>'/')=>hashfile(joinpath(d, f)) for
        (d, _, fs) in walkdir(folder) for f in fs
    )
end
function freeze(dest)
    ispath(dest) && error("不覆盖灾前冻结输入")
    protocol=joinpath(ROOT, "configs/r9/preplan-study.toml")
    p=TOML.parsefile(protocol)
    parent=joinpath(ROOT, p["parent_input"])
    PreviousInput.resilience_read(parent; current_code = false)
    hashfile(joinpath(parent, "files.toml"))==p["parent_manifest_sha256"] || error("原输入身份不符")
    key=p["critical_set"]
    c=load_r7_planning_case(
        joinpath(parent, key, "normal.toml"),
        joinpath(parent, key, "planning.toml"),
    )
    d=TOML.parsefile(joinpath(parent, key, "construction.toml"))
    pairs=[(event = 1, fault = d["pilot_faults"][id]) for id in p["fault_ids"]]
    stage=dest*".writing-"*string(uuid4())
    mkpath(stage)
    cp(protocol, joinpath(stage, "protocol.toml"))
    for file in ("normal.toml", "planning.toml", "construction.toml")
        cp(joinpath(parent, key, file), joinpath(stage, file))
    end
    cp(joinpath(parent, "protocol.toml"), joinpath(stage, "parent-protocol.toml"))
    cp(joinpath(parent, "files.toml"), joinpath(stage, "parent-files.toml"))
    for mode in p["modes"]
        s=r9_preplan_spec(
            c;
            mode,
            pairs,
            penalty_MWh = p["penalty_CNY_MWh"],
            limits_MWh = [p["loss_limit_MWh"]],
        )
        write(joinpath(stage, mode*"-spec.toml"), PR.r7_text(s))
    end
    for (p, file) in science()
        target=joinpath(stage, "code", p)
        mkpath(dirname(target))
        cp(file, target)
    end
    manifest=Dict(
        "schema"=>"r9-preplan-input-v1",
        "files"=>filehashes(stage),
        "code"=>sort(collect(keys(science()))),
        "optimization_performed"=>false,
        "parent_manifest_sha256"=>p["parent_manifest_sha256"],
        "utc"=>string(now(UTC)),
    )
    write(joinpath(stage, "files.toml"), PR.r7_text(manifest))
    mv(stage, dest)
    readinput(dest)
    println(
        "Frozen preplan input ",
        replace(relpath(dest, ROOT), '\\'=>'/'),
        " sha256=",
        hashfile(joinpath(dest, "files.toml")),
    )
end
function readinput(folder; current_code = true)
    m=TOML.parsefile(joinpath(folder, "files.toml"))
    m["schema"]=="r9-preplan-input-v1" || error("灾前输入冻结版本错误")
    actual=filehashes(folder)
    delete!(actual, "files.toml")
    actual==m["files"] && all(safe, keys(m["files"])) || error("灾前输入字节/集合被改变")
    p=TOML.parsefile(joinpath(folder, "protocol.toml"))
    hashfile(joinpath(folder, "parent-files.toml"))==p["parent_manifest_sha256"]==m["parent_manifest_sha256"] ||
        error("父输入清单不符")
    parent=TOML.parsefile(joinpath(folder, "parent-files.toml"))
    for file in ("normal.toml", "planning.toml", "construction.toml")
        hashfile(joinpath(folder, file))==parent["files"][p["critical_set"]*"/"*file] ||
            error("正常物理输入或故障改变")
    end
    if current_code
        Set(keys(science()))==Set(m["code"]) || error("当前源码集合改变")
        all(hashfile(f)==m["files"]["code/"*k] for (k, f) in science()) ||
            error("源码改变，须另建冻结版本")
    end
    c=load_r7_planning_case(joinpath(folder, "normal.toml"), joinpath(folder, "planning.toml"))
    for mode in p["modes"]
        s=TOML.parsefile(joinpath(folder, mode*"-spec.toml"))
        PR.r9_preplan_check(c, s)
        s["mode"]==mode || error("方案标签与输入不一致")
    end
    (; case = c, protocol = p, manifest = m)
end
function transport(c, event, p)
    ev=only(c.specification["events"])
    win=ev["event_start"]:(ev["event_start"]+ev["periods"]-1)
    flows=Dict(
        "m_pipe"=>reduce(
            vcat,
            [permutedims(x["normal_flow_kg_s"][win]) for x in c.normal.data["heat"]["pipes"]],
        ),
        "m_source"=>reduce(
            vcat,
            [permutedims(x[win]) for x in c.normal.data["heat"]["source_flow_kg_s"]],
        ),
        "m_load"=>reduce(
            vcat,
            [permutedims(x[win]) for x in c.normal.data["heat"]["load_flow_kg_s"]],
        ),
    )
    r7_transport_spec(
        event.case;
        flow_schedule = flows,
        profiles = event.evidence["initial_pipe_profiles"],
        profile_origin = "inherited complete normal state; parent="*event.evidence["parent_run_id"],
        substeps = p["recovery_substeps"],
    )
end
function run(folder, out, mode)
    x=readinput(folder)
    c, p=x.case, x.protocol
    mode in p["modes"] || error("未冻结的方法")
    dest=joinpath(out, mode)
    ispath(dest) && error("不覆盖完整方法运行")
    mkpath(dest)
    opt=optimizer_with_attributes(
        Gurobi.Optimizer,
        "OutputFlag"=>0,
        "Threads"=>1,
        "FeasibilityTol"=>1e-9,
        "IntFeasTol"=>1e-9,
        "OptimalityTol"=>1e-9,
        "MIPGap"=>1e-4,
    )
    s=TOML.parsefile(joinpath(folder, mode*"-spec.toml"))
    println(mode, " primary start elapsed=", time()-STARTED)
    flush(stdout)
    stop=STARTED+p["primary_deadline_sec"]
    r=solve_r9_preplan(c, s; optimizer = opt, budget_sec = max(0, stop-time()), deadline = stop)
    save_r9_preplan(c, s, r, joinpath(dest, "primary"))
    println(
        mode,
        " primary ",
        r["status"],
        " accepted=",
        r["candidate_accepted"],
        " elapsed=",
        time()-STARTED,
    )
    flush(stdout)
    stages=Any[]
    todo=[
        (i = i, kind = kind) for i in eachindex(p["fault_ids"]) for
        kind in ("aggregate", "detailed")
    ]
    if r["candidate_accepted"] && time()<STARTED+p["recovery_deadline_sec"]
        event=PR.r7_planning_event(c, r["master"]["normal"], 1)
        write(joinpath(dest, "event.toml"), PR.r7_text(event.case.data))
        write(joinpath(dest, "inheritance.toml"), PR.r7_text(event.evidence))
        ts=transport(c, event, p)
        write(joinpath(dest, "transport-spec.toml"), PR.r7_text(ts))
        for (k, job) in enumerate(todo)
            label=job.kind*"-"*p["fault_ids"][job.i]
            start=time()
            remaining=STARTED+p["recovery_deadline_sec"]-start
            allowance=max(0, min(p["recovery_max_sec"], remaining/(length(todo)-k+1)))
            if allowance<=0
                push!(
                    stages,
                    Dict("stage"=>label, "status"=>"budget_exhausted", "attempted"=>false),
                )
                continue
            end
            fault=s["pairs"][job.i]["fault"]
            println(mode, " ", label, " start budget=", allowance)
            flush(stdout)
            if job.kind=="aggregate"
                rec=solve_r7_recovery(
                    event.case,
                    fault;
                    optimizer = opt,
                    budget_sec = allowance,
                    deadline = start+allowance,
                )
                save_r7_recovery(event.case, rec, joinpath(dest, label))
            else
                rec=solve_r7_transport_recovery(
                    event.case,
                    fault,
                    ts;
                    optimizer = opt,
                    budget_sec = allowance,
                    deadline = start+allowance,
                )
                save_r7_transport_recovery(event.case, ts, rec, joinpath(dest, label))
            end
            q=rec["validation"]
            push!(
                stages,
                Dict(
                    "stage"=>label,
                    "status"=>rec["status"],
                    "attempted"=>true,
                    "run_id"=>rec["run_id"],
                    "model_pass"=>q["model_pass"],
                    "loss_MWh"=>get(q, "loss_MWh", NaN),
                    "elapsed_sec"=>time()-start,
                    "requested_stage_sec"=>allowance,
                ),
            )
            println(
                mode,
                " ",
                label,
                " ",
                rec["status"],
                " model=",
                q["model_pass"],
                " loss=",
                get(q, "loss_MWh", NaN),
            )
            flush(stdout)
        end
    else
        for job in todo
            push!(
                stages,
                Dict(
                    "stage"=>job.kind*"-"*p["fault_ids"][job.i],
                    "status"=>r["candidate_accepted"] ? "budget_exhausted" : "no_accepted_parent",
                    "attempted"=>false,
                ),
            )
        end
    end
    receipt=Dict{String,Any}(
        "schema"=>"r9-preplan-execution-v1",
        "mode"=>mode,
        "input_manifest_sha256"=>hashfile(joinpath(folder, "files.toml")),
        "primary_run_id"=>r["run_id"],
        "primary_status"=>r["status"],
        "stages"=>stages,
        "budget_sec"=>p["budget_sec"],
        "source_hashes"=>Dict(k=>hashfile(v) for (k, v) in science()),
        "whole_fault_universe_certified"=>false,
        "free_flow_preplan_certified"=>false,
    )
    # 原记录与当前源码再次一致才封口；最终耗时包括全部阶段的回放和保存。
    readinput(folder)
    write(joinpath(dest, "files.toml"), PR.r7_text(Dict("files"=>filehashes(dest))))
    receipt["total_wall_sec"]=time()-STARTED
    receipt["budget_pass"]=receipt["total_wall_sec"]<=p["budget_sec"]
    write(joinpath(dest, "execution.toml"), PR.r7_text(receipt))
    println(
        mode,
        " completed wall=",
        receipt["total_wall_sec"],
        " budget_pass=",
        receipt["budget_pass"],
    )
end

if abspath(PROGRAM_FILE)==@__FILE__
    if length(ARGS)==2 && ARGS[1]=="freeze"
        freeze(abspath(ARGS[2]))
    elseif length(ARGS)==2 && ARGS[1]=="check"
        readinput(abspath(ARGS[2]))
        println("Preplan frozen input passed.")
    elseif length(ARGS)==4 && ARGS[1]=="run"
        @eval using Gurobi
        try
            Base.invokelatest(run, abspath(ARGS[2]), abspath(ARGS[3]), ARGS[4])
        catch err
            ARGS[4] in ("economic", "penalty", "threshold") || rethrow()
            dest=joinpath(abspath(ARGS[3]), ARGS[4])
            mkpath(dest)
            file=joinpath(dest, "pipeline-failure.toml")
            ispath(file) || write(
                file,
                PR.r7_text(
                    Dict(
                        "status"=>"pipeline_error",
                        "error_type"=>string(typeof(err)),
                        "elapsed_sec"=>time()-STARTED,
                    ),
                ),
            )
            rethrow()
        end
    else
        error(
            "usage: r9_preplan_study.jl freeze NEW_INPUT | check INPUT | run INPUT NEW_OUTPUT MODE",
        )
    end
end
end
