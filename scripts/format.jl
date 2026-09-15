using JuliaFormatter

root = normpath(joinpath(@__DIR__, ".."))
fix = "--fix" in ARGS
paths = [joinpath(root, folder) for folder in ("src", "test", "scripts")]
push!(paths, joinpath(root, "docs", "make.jl"))
ok = all([format(path; overwrite = fix) for path in paths])
if !ok && !fix
    error("Julia formatting differs. Run the same command with --fix, then inspect the diff.")
end
println(fix ? "Julia formatting applied." : "Julia formatting passed.")
