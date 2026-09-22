"""串行启动冻结方法；同一方法的启动、加载、求解、核验和保存共享墙钟上限。"""
module R9ScalabilityBatch
using TOML, SHA, Dates
include("r9_trading_study.jl")
using .R9TradingStudy: safe, hashfile, toml, clock

"""只监视本次创建的子进程；到期终止该句柄，保留日志和已经写出的原始证据。"""
function watch(cmd, logpath; budget_sec, start = clock(), poll_sec = 0.05, on_started = nothing)
    isfinite(budget_sec) && budget_sec>0 || error("Invalid wall budget")
    isfinite(start) && start<=clock() || error("Invalid monotonic start")
    isfinite(poll_sec) && 0<poll_sec<=1 || error("Invalid polling interval")
    ispath(logpath) && error("Do not overwrite process log")
    process=nothing
    pid=0
    timed_out=false
    try
        open(logpath, "w") do io
            process=run(pipeline(ignorestatus(cmd), stdout = io, stderr = io); wait = false)
            pid=getpid(process)
            on_started===nothing || on_started(pid)
            while process_running(process)
                remaining=start+budget_sec-clock()
                if remaining<=0
                    timed_out=true
                    # SIGKILL在Windows同样终止已知句柄，不按名称查找/终止其它Julia进程。
                    kill(process, Base.SIGKILL)
                    break
                end
                sleep(min(poll_sec, remaining))
            end
            wait(process)
        end
    catch
        if process!==nothing && process_running(process)
            kill(process, Base.SIGKILL)
            wait(process)
        end
        rethrow()
    end
    elapsed=clock()-start
    (;
        exit_code = Int(process.exitcode),
        term_signal = Int(process.termsignal),
        process_success = success(process),
        process_elapsed_sec = elapsed,
        process_budget_pass = elapsed<=budget_sec,
        timed_out,
        pid,
    )
end

"""12方法固定顺序、独立进程；逐项保存启动和终止收据，失败不抹去其它方法。"""
function launch(study)
    VERSION==v"1.12.6" || error("Use Julia 1.12.6")
    meta=TOML.parsefile(safe(study, "manifest.toml"))
    meta["schema"]=="r9-scalability-study-v1" || error("Study identity")
    for (rel, h) in meta["files"]
        hashfile(safe(study, rel))==h || error("Frozen bytes changed: $rel")
    end
    hashfile(@__FILE__)==meta["files"]["code/scripts/run_r9_scalability_batch.jl"] ||
        error("Use frozen launcher")
    meta["protocol"]["hard_timeout"] && meta["protocol"]["budget_sec"]==600 ||
        error("Deadline protocol")
    methods=meta["methods"]
    methods==meta["protocol"]["methods"] && length(methods)==12 || error("Method inventory")
    # 启动前检查所有目标，拒绝把第二次尝试混入原批次。
    for rel in ("batch-started.toml", "batch-receipt.toml", "launches", "logs", "runs")
        ispath(safe(study, rel)) && error("Do not overwrite/resume an existing batch: $rel")
    end
    identity=Dict(
        "schema"=>"r9-scalability-batch-v1",
        "manifest_sha256"=>hashfile(safe(study, "manifest.toml")),
        "launcher_sha256"=>hashfile(@__FILE__),
        "started_utc"=>string(now(UTC)),
        "budget_sec"=>600.0,
        "method_order"=>[x["id"] for x in methods],
    )
    mkpath(safe(study, "launches"))
    mkpath(safe(study, "logs"))
    toml(safe(study, "batch-started.toml"), identity)
    rows=Dict{String,Any}[]
    script=safe(study, "code/scripts/r9_scalability_study.jl")
    for entry in methods
        id=entry["id"]
        occursin(r"^ag(8|16|32)-(fixed|mip)-(central|admm)$", id) || error("Method ID")
        project=safe(study, entry["solver"]=="Clarabel" ? "code" : "code/tools/solvers")
        started=string(now(UTC))
        start=clock()
        cmd=`$(Base.julia_cmd()) --startup-file=no --threads=1 --project=$project $script run $study $id $start`
        println("START ", id)
        flush(stdout)
        row=Dict{String,Any}(
            "id"=>id,
            "entry"=>entry,
            "started_utc"=>started,
            "manifest_sha256"=>identity["manifest_sha256"],
            "budget_sec"=>600.0,
        )
        try
            result=watch(
                cmd,
                safe(study, "logs/$id.log");
                budget_sec = 600.0,
                start,
                on_started = pid->toml(
                    safe(study, "launches/$id-started.toml"),
                    merge(row, Dict("pid"=>pid)),
                ),
            )
            merge!(row, Dict(string(k)=>v for (k, v) in pairs(result)))
            row["process_status"]=result.timed_out ? "hard_timeout" :
                                  result.process_success ? "exited_zero" : "exited_nonzero"
        catch err
            err isa InterruptException && rethrow()
            row["process_status"]="launcher_error"
            row["error_type"]=string(typeof(err))
            row["process_elapsed_sec"]=clock()-start
            row["process_budget_pass"]=row["process_elapsed_sec"]<=600
        end
        row["finished_utc"]=string(now(UTC))
        row["log_sha256"]=hashfile(safe(study, "logs/$id.log"))
        toml(safe(study, "launches/$id.toml"), row)
        push!(rows, row)
        println(
            "EXIT ",
            id,
            " ",
            row["process_status"],
            " ",
            round(row["process_elapsed_sec"]; digits = 3),
            " s",
        )
        flush(stdout)
    end
    toml(
        safe(study, "batch-receipt.toml"),
        merge(
            identity,
            Dict(
                "methods"=>rows,
                "finished_utc"=>string(now(UTC)),
                "all_processes_exited_zero"=>all(x->x["process_status"]=="exited_zero", rows),
            ),
        ),
    )
    println(
        "All 12 frozen methods have terminal process records; scientific success is checked separately.",
    )
    rows
end

function main(args)
    length(args)==1 || error("Usage: run_r9_scalability_batch.jl STUDY")
    launch(abspath(only(args)))
end
end
abspath(PROGRAM_FILE)==abspath(@__FILE__) && R9ScalabilityBatch.main(ARGS)
