# 四模式直接参考：先冻结规则、源码及环境，再逐项执行；不调用或注入PG。
using TOML, SHA, Dates
root = dirname(@__DIR__)
length(ARGS) == 1 || error("usage: r9_flow_reference.jl NEW_DIRECTORY")
out = abspath(only(ARGS))
ispath(out) && error("Refuse to overwrite a study")
hashfile(p) = bytes2hex(sha256(read(p)))
toml(p, x) = open(io->TOML.print(io, x; sorted = true), p, "w")
protocol_path = joinpath(root, "configs/r9/flow-reference.toml")
protocol = TOML.parsefile(protocol_path)
parent = joinpath(root, protocol["input_parent"])
hashfile(joinpath(parent, "case.toml")) == protocol["input_sha256"] || error("Input hash changed")
science = [
    TOML.parsefile(joinpath(parent, "manifest.toml"))["science_files"];
    ["src/networks/r9_short_pipe.jl", "src/formulations/r9_flow.jl", "src/verification/r9_flow.jl"]
]
tracked = [
    science;
    [
        "scripts/r9_flow_probe.jl",
        "scripts/gurobi_primal_start.jl",
        "scripts/r9_flow_reference.jl",
        "configs/r9/flow-reference.toml",
        "Project.toml",
        "Manifest.toml",
        "tools/solvers/Project.toml",
        "tools/solvers/Manifest.toml",
    ]
]
mkpath(out)
files = Dict{String,String}()
for path in tracked
    target = joinpath(out, "frozen", path)
    mkpath(dirname(target))
    cp(joinpath(root, path), target)
    files[path] = hashfile(target)
end
cp(joinpath(parent, "case.toml"), joinpath(out, "case.toml"))
toml(joinpath(out, "protocol.toml"), protocol)
toml(
    joinpath(out, "manifest.toml"),
    Dict(
        "schema"=>"r9-flow-reference-study-v1",
        "started_utc"=>string(now(UTC)),
        "files"=>files,
        "science_files"=>science,
        "julia_version"=>string(VERSION),
        "git_head"=>strip(read(`git -C $root rev-parse HEAD`, String)),
    ),
)
for mode in protocol["modes"]
    all(hashfile(joinpath(root, p))==h for (p, h) in files) ||
        error("Frozen source changed during study")
    folder=joinpath(out, "runs", lowercase(mode))
    runner=joinpath(root, "scripts/r9_flow_probe.jl")
    command=`$(Base.julia_cmd()) --startup-file=no --project=$(joinpath(root,"tools/solvers")) $runner $folder $mode true $(protocol["budget_sec"]) local drop_implied_cones 0`
    start=time_ns()/1e9
    open(joinpath(out, lowercase(mode)*".log"), "w") do io
        process=run(pipeline(ignorestatus(command), stdout = io, stderr = io))
        elapsed=time_ns()/1e9-start
        toml(
            joinpath(out, lowercase(mode)*"-execution.toml"),
            Dict(
                "exitcode"=>process.exitcode,
                "wall_sec_including_imports"=>elapsed,
                "budget_sec"=>protocol["budget_sec"],
                "wall_budget_pass"=>elapsed<=protocol["budget_sec"],
                "mode"=>mode,
            ),
        )
        println(mode, " exit=", process.exitcode, " wall_sec=", elapsed)
        flush(stdout)
    end
end
all(hashfile(joinpath(root, p))==h for (p, h) in files) || error("Source changed during study")
println("Four-mode reference completed; science acceptance requires independent readback.")
