# Optional local solver qualification environment; does not change the root project.
using Pkg

function bootstrap_solvers()
    VERSION == v"1.12.6" || error("Use Julia 1.12.6.")
    environment = normpath(joinpath(@__DIR__, "..", "tools", "solvers"))
    Pkg.activate(environment)
    Pkg.instantiate()
    println("Solver qualification environment ready; no thesis experiment was run.")
end

if abspath(PROGRAM_FILE) == @__FILE__
    bootstrap_solvers()
end
