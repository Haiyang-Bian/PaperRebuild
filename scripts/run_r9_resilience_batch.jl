# 按冻结协议串行运行六项恢复；每次新的Julia进程各自执行完整600秒预算。
using TOML
root=dirname(@__DIR__)
length(ARGS)==3 || error("usage: run_r9_resilience_batch.jl INPUT OUTPUT CRITICAL_SET")
bundle, out, key=abspath(ARGS[1]), abspath(ARGS[2]), ARGS[3]
p=TOML.parsefile(joinpath(bundle, "protocol.toml"))
key in p["critical_sets"] || error("未声明的关键分类")
stages=[mode*"-"*fault for mode in ("aggregate", "detailed") for fault in p["pilot"]["fault_ids"]]
logs=joinpath(out, "logs", key)
mkpath(logs)
for stage in stages
    log=joinpath(logs, stage*".log")
    ispath(log) && error("已有运行日志，请明确核查而不是自动重跑：$stage")
    println("Starting ", key, " ", stage)
    flush(stdout)
    cmd=`$(Base.julia_cmd()) --startup-file=no $("--project="*joinpath(root,"tools/solvers")) $(joinpath(root,"scripts/r9_resilience_study.jl")) run $bundle $out $key $stage`
    process=open(log, "w") do io
        run(pipeline(ignorestatus(cmd); stdout = io, stderr = io))
    end
    println("Completed ", stage, " exit=", process.exitcode)
    flush(stdout)
    process.exitcode==0 || error("执行管道失败；先核查$(stage)日志，未开始的阶段保持未运行")
end
