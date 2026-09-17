include("r4_setup.jl")
length(ARGS)>=1 || error("提供同输入的运行目录")
for row in compare_r4_runs(ARGS)
    println(row)
end
