using PaperRebuild

length(ARGS) == 1 || error("用法: check_r6_data.jl <冻结数据目录>")
r = read_r6_dataset(ARGS[1])
println("R6 frozen input replay passed: ", r.protocol.sha256)
println(
    "Split counts: ",
    r.protocol.data["samples"],
    "; clustering iterations: ",
    r.representatives["iterations"],
)
