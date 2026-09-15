using LiveServer

include(joinpath(@__DIR__, "..", "docs", "make.jl"))
serve(; dir = joinpath(@__DIR__, "..", "docs", "build"), host = "127.0.0.1", port = 8000)
