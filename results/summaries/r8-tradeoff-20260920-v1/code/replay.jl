include("../r8_archive.jl")
x=r8_archive_check(joinpath(@__DIR__,".."))
println(length(x.records)," frozen R8 records checked")
