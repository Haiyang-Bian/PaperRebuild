# 每方法独立Julia进程，按冻结清单顺序运行；不根据结果替换输入或增加预算。
using TOML
length(ARGS)==1 || error("usage: run_r9_network_batch.jl STUDY")
study=abspath(only(ARGS))
meta=TOML.parsefile(joinpath(study, "manifest.toml"))
for entry in meta["methods"]
    id=entry["id"]
    logdir=joinpath(study, "logs")
    mkpath(logdir)
    logpath=joinpath(logdir, id*".log")
    ispath(logpath) && error("Do not overwrite prior batch output")
    script=joinpath(study, "code/scripts/r9_network_study.jl")
    project=joinpath(study, "code/tools/solvers")
    cmd=`$(Base.julia_cmd()) --startup-file=no --project=$project $script run $study $id`
    println("START ", id)
    flush(stdout)
    open(logpath, "w") do io
        result=Base.run(pipeline(ignorestatus(cmd), stdout = io, stderr = io))
        println("EXIT ", id, " ", result.exitcode)
        flush(stdout)
        success(result) || error("Method process failed; evidence kept: "*id)
    end
end
println("All frozen methods reached a terminal process state.")
