using SHA, TOML, PaperRebuild
length(ARGS)==2||error("参数：环境失败保留目录 完成的审计目录")
failed, complete=abspath.(ARGS)
isfile(joinpath(complete, "audit.toml"))||error("复核尚未完成")
isfile(joinpath(failed, "audit.toml"))&&error("首轮不应已有完成元数据")
matched=Dict{String,String}()
for (base, _, files) in walkdir(failed), file in files
    path=joinpath(base, file)
    rel=replace(relpath(path, failed), '\\'=>'/')
    other=joinpath(complete, split(rel, '/')...)
    isfile(other)&&read(path)==read(other)||error("环境复核原值改变：$rel")
    matched[rel]=bytes2hex(sha256(read(path)))
end
length(matched)==27||error("失败阶段输出清单不同")
dest=joinpath(complete, "environment-replay.toml")
ispath(dest)&&error("不覆盖环境复核证据")
meta=Dict(
    "schema"=>"r5-duality-environment-replay-v1",
    "first_attempt_status"=>"metadata_git_read_pipe_EBADF",
    "first_attempt_terminal_code"=>1,
    "rerun_solver_executed"=>false,
    "identical_files"=>matched,
    "script_sha256"=>bytes2hex(sha256(read(@__FILE__))),
    "scope"=>"All 24 witnesses and three CSV outputs unchanged; successful rerun adds missing completion metadata.",
)
write(dest, PaperRebuild.r5_market_text(meta))
println("Environment replay: 27 witness/CSV files byte-identical; no solver executed.")
