let depot=normpath(joinpath(@__DIR__, "..", ".julia"))
    isdir(depot) && !(depot in DEPOT_PATH) && pushfirst!(DEPOT_PATH, depot)
end
using Test, PaperRebuild
include(joinpath(@__DIR__, "..", "test", "r3_pg.jl"))
