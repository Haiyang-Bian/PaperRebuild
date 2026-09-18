using PaperRebuild, TOML
include("r4_distributed_docs.jl")
sync_r4_distributed(; check = !("--sync" in ARGS))
args=filter(x->!startswith(x, "--"), ARGS)
if !isempty(args)
    length(args)==1 || error("仅提供一个已保存运行目录")
    println(read_r4_distributed_run(only(args)).validation)
end
