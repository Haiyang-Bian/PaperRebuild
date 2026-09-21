# 独立命令逐项执行，输入冻结先于任何规模优化；原运行不覆盖。
const R9_RESILIENCE_STARTED=time()
using PaperRebuild, JuMP, TOML, SHA, Dates
const PR=PaperRebuild
const ROOT=dirname(@__DIR__)

function resilience_code()
    merge(
        PR.r7_normal_science_paths(),
        PR.r7_transport_science_paths(),
        Dict(
            p=>joinpath(ROOT, p) for p in (
                "src/core/r9_resilience.jl",
                "src/core/r9_inputs.jl",
                "src/core/r9_pv.jl",
                "src/verification/r9_sources.jl",
                "scripts/r9_resilience_study.jl",
            )
        ),
    )
end
function resilience_freeze(dest)
    ispath(dest) && error("不覆盖保供输入")
    proto=joinpath(ROOT, "configs/r9/resilience-protocol.toml")
    p=TOML.parsefile(proto)
    stage=dest*".writing"
    ispath(stage) && error("未完成冻结目录已存在")
    mkpath(stage)
    for key in p["critical_sets"]
        x=r9_resilience_template(joinpath(ROOT, "docs/reading/ch07"), proto; critical_set = key)
        folder=joinpath(stage, key)
        mkpath(folder)
        for (file, data) in (
            ("normal.toml", x.normal.data),
            ("planning.toml", x.planning.specification),
            ("construction.toml", x.evidence),
        )
            write(joinpath(folder, file), PR.r7_text(data))
        end
    end
    cp(proto, joinpath(stage, "protocol.toml"))
    for file in ("inputs.toml", "topology.toml", "reported-results.toml", "resilience-review.toml")
        mkpath(joinpath(stage, "source"))
        cp(joinpath(ROOT, "docs/reading/ch07", file), joinpath(stage, "source", file))
    end
    code=resilience_code()
    for (p, file) in code
        target=joinpath(stage, "code", p)
        mkpath(dirname(target))
        cp(file, target)
    end
    hashes=Dict(
        replace(relpath(joinpath(dir, f), stage), '\\'=>'/')=>bytes2hex(
            sha256(read(joinpath(dir, f))),
        ) for (dir, _, files) in walkdir(stage) for f in files
    )
    manifest=Dict(
        "schema"=>"r9-resilience-freeze-v1",
        "origin"=>p["origin"],
        "utc"=>string(now(UTC)),
        "files"=>hashes,
        "code"=>sort(collect(keys(code))),
        "optimization_performed"=>false,
    )
    write(joinpath(stage, "files.toml"), PR.r7_text(manifest))
    mv(stage, dest)
    println(
        "Frozen: ",
        relpath(dest, ROOT),
        " sha256=",
        bytes2hex(sha256(read(joinpath(dest, "files.toml")))),
    )
end
function resilience_read(bundle; current_code = true)
    d=TOML.parsefile(joinpath(bundle, "files.toml"))
    d["schema"]=="r9-resilience-freeze-v1" || error("冻结版本错误")
    actual=Set(
        replace(relpath(joinpath(dir, f), bundle), '\\'=>'/') for (dir, _, files) in
                                                                  walkdir(bundle) for f in files
    )
    actual==union(Set(keys(d["files"])), Set(["files.toml"])) || error("冻结文件集合改变")
    for (p, h) in d["files"]
        !isabspath(p) && !occursin(':', p) && all(x->!(x in ("..", ".")), split(p, '/')) ||
            error("非法冻结路径")
        bytes2hex(sha256(read(joinpath(bundle, p))))==h || error("冻结字节改变：$p")
    end
    if current_code
        code=resilience_code()
        Set(keys(code))==Set(d["code"]) || error("当前源码入口与冻结不一致")
        for (p, file) in code
            bytes2hex(sha256(read(file)))==d["files"]["code/"*p] ||
                error("源码改变，请建立新冻结版本：$p")
        end
    end
    d
end
function resilience_run(bundle, out, key, stage)
    ispath(joinpath(out, key, stage)) && error("不覆盖已有保供运行")
    frozen=resilience_read(bundle)
    p=TOML.parsefile(joinpath(bundle, "protocol.toml"))
    key in p["critical_sets"] || error("未知关键节点分类")
    normal=load_r7_normal_case(joinpath(bundle, key, "normal.toml"))
    specification=TOML.parsefile(joinpath(bundle, key, "planning.toml"))
    construction=TOML.parsefile(joinpath(bundle, key, "construction.toml"))
    opt=optimizer_with_attributes(
        Gurobi.Optimizer,
        "OutputFlag"=>0,
        "Threads"=>1,
        "FeasibilityTol"=>1e-9,
        "IntFeasTol"=>1e-9,
        "OptimalityTol"=>1e-9,
        "MIPGap"=>1e-4,
    )
    dest=joinpath(out, key, stage)
    if stage=="normal"
        stop=R9_RESILIENCE_STARTED+p["normal_solve_deadline_sec"]
        r=solve_r7_normal(
            normal;
            optimizer = opt,
            budget_sec = max(0, stop-time()),
            deadline = stop,
        )
        save_r7_normal(normal, r, dest)
    else
        bits=split(stage, '-'; limit = 2)
        length(bits)==2 && bits[1] in ("aggregate", "detailed") || error("未知预运行阶段")
        mode, faultid=bits
        haskey(construction["pilot_faults"], faultid) || error("故障不属于冻结预运行清单")
        parent=read_r7_normal(joinpath(out, key, "normal"))
        parent.case.sha256==normal.sha256 || error("正常运行父输入不同")
        ev=only(specification["events"])
        event=r7_normal_event(
            normal,
            parent.result;
            event_start = ev["event_start"],
            periods = ev["periods"],
            renewable_factor = ev["renewable_factor"],
            loss_limit_MWh = ev["loss_limit_MWh"],
        )
        c=with_r7_port_temperature_bounds(event.case)
        fault=construction["pilot_faults"][faultid]
        stop=R9_RESILIENCE_STARTED+p["recovery_solve_deadline_sec"]
        if mode=="aggregate"
            r=solve_r7_recovery(
                c,
                fault;
                optimizer = opt,
                budget_sec = max(0, stop-time()),
                deadline = stop,
            )
            save_r7_recovery(c, r, dest)
        else
            win=ev["event_start"]:(ev["event_start"]+ev["periods"]-1)
            flows=Dict(
                "m_pipe"=>reduce(
                    vcat,
                    [
                        permutedims(pipe["normal_flow_kg_s"][win]) for
                        pipe in normal.data["heat"]["pipes"]
                    ],
                ),
                "m_source"=>reduce(
                    vcat,
                    [permutedims(row[win]) for row in normal.data["heat"]["source_flow_kg_s"]],
                ),
                "m_load"=>reduce(
                    vcat,
                    [permutedims(row[win]) for row in normal.data["heat"]["load_flow_kg_s"]],
                ),
            )
            spec=r7_transport_spec(
                c;
                flow_schedule = flows,
                profiles = event.evidence["initial_pipe_profiles"],
                profile_origin = "inherited complete normal parcel state; parent="*parent.result["run_id"],
                substeps = p["heat"]["recovery_substeps"],
            )
            r=solve_r7_transport_recovery(
                c,
                fault,
                spec;
                optimizer = opt,
                budget_sec = max(0, stop-time()),
                deadline = stop,
            )
            save_r7_transport_recovery(c, spec, r, dest)
        end
        record=Dict(
            "parent_normal_run_id"=>parent.result["run_id"],
            "parent_normal_result_sha256"=>PR.r7_digest(parent.result),
            "event_boundary"=>event.evidence,
            "adopted_event_case_sha256"=>c.sha256,
        )
        write(dest*"-inheritance.toml", PR.r7_text(record))
    end
    summary=Dict(
        "stage"=>stage,
        "critical_set"=>key,
        "input_manifest_sha256"=>bytes2hex(sha256(read(joinpath(bundle, "files.toml")))),
        "status"=>r["status"],
        "run_id"=>r["run_id"],
        "total_wall_sec"=>time()-R9_RESILIENCE_STARTED,
        "budget_sec"=>p["budget_sec"],
        "budget_pass"=>time()-R9_RESILIENCE_STARTED<=p["budget_sec"],
        "whole_fault_universe_certified"=>false,
        "free_flow_preplan_certified"=>false,
    )
    write(dest*"-execution.toml", PR.r7_text(summary))
    println(PR.r7_text(summary))
    println("validation model_pass=", get(r["validation"], "model_pass", false))
end

if abspath(PROGRAM_FILE)==@__FILE__
    !isempty(ARGS) || error(
        "usage: r9_resilience_study.jl freeze BUNDLE | run BUNDLE OUTPUT SET STAGE | check BUNDLE",
    )
    if ARGS[1]=="freeze" && length(ARGS)==2
        resilience_freeze(abspath(ARGS[2]))
    elseif ARGS[1]=="run" && length(ARGS)==5
        # Julia 1.12的模块绑定也有world age；先在顶层加载，再于最新world进入整个运行。
        @eval using Gurobi
        try
            Base.invokelatest(resilience_run, abspath(ARGS[2]), abspath(ARGS[3]), ARGS[4], ARGS[5])
        catch err
            folder=joinpath(abspath(ARGS[3]), ARGS[4])
            mkpath(folder)
            failure=joinpath(folder, ARGS[5]*"-pipeline-failure.toml")
            if !ispath(failure)
                write(
                    failure,
                    PR.r7_text(
                        Dict(
                            "status"=>"pipeline_error",
                            "stage"=>ARGS[5],
                            "error_type"=>string(typeof(err)),
                            "elapsed_sec"=>time()-R9_RESILIENCE_STARTED,
                            "input_manifest_sha256"=>bytes2hex(
                                sha256(read(joinpath(abspath(ARGS[2]), "files.toml"))),
                            ),
                        ),
                    ),
                )
            end
            rethrow()
        end
    elseif ARGS[1]=="check" && length(ARGS)==2
        resilience_read(abspath(ARGS[2]))
        println("Frozen input hashes and current model sources passed.")
    else
        error("不支持的运行参数")
    end
end
