# 按预冻结顺序运行，各方法独立进程；实际失败仍保留，不替换数据或自动重试。
using TOML
length(ARGS)==3 || error("usage: run_r9_reserve_batch.jl STUDY pilot|full NEW_OUTPUT")
study, phase, out=abspath(ARGS[1]), ARGS[2], abspath(ARGS[3])
phase in ("pilot", "full") || error("Phase must be pilot or full")
ispath(out) && error("Do not overwrite earlier batch")
mkpath(out)
m=TOML.parsefile(joinpath(study, "manifest.toml"))
for e in m["methods"]
    e["pilot"]==(phase=="pilot") || continue
    id=e["id"]
    script=joinpath(study, "code/scripts/r9_reserve_study.jl")
    project=joinpath(study, "code")
    target=joinpath(out, id)
    cmd=`$(Base.julia_cmd()) --startup-file=no --project=$project $script run $study $id $target`
    println("START ", id)
    flush(stdout)
    open(joinpath(out, id*".log"), "w") do io
        result=run(pipeline(ignorestatus(cmd), stdout = io, stderr = io))
        println("EXIT ", id, " ", result.exitcode)
        flush(stdout)
        success(result) || error("Process failure preserved: $id")
    end
end
println("All selected methods have terminal records; inspect scientific checks separately.")
