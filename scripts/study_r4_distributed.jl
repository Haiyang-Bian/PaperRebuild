include("r4_setup.jl")
using Dates, SHA
root=normpath(joinpath(@__DIR__, ".."))
config=joinpath(root, "configs", "r4", "distributed-study.toml")
d=TOML.parsefile(config)
batch=isempty(ARGS) ? "r4-distributed-"*Dates.format(now(), "yyyymmddTHHMMSS") : only(ARGS)
occursin(r"^[A-Za-z0-9_-]+$", batch) || error("非法批次名")
dest=joinpath(root, "results", "runs", "r4", batch)
ispath(dest) && error("不覆盖旧批次")
jobs=[
    (; name, pattern, purpose, solver = d["primary_solver"]) for name in d["cases"] for
    pattern in eachindex(d["patterns"]) for purpose in d["purposes"]
]
append!(
    jobs,
    [
        (;
            name,
            pattern = d["cross_pattern"],
            purpose = d["cross_purpose"],
            solver = d["cross_solver"],
        ) for name in d["cross_cases"]
    ],
)
cases=Dict(
    name=>load_r4_case(joinpath(root, "configs", "r4", "baseline", name*".toml")) for
    name in d["cases"]
)
all(cases[name].sha256==d["input_sha256"][name] for name in d["cases"]) || error("冻结输入改变")
length(jobs)==d["expected_distributed_runs"] || error("冻结运行数不符")
spec=R4DistributedSpec(
    rho = d["rho"],
    peer_rho = d["peer_rho"],
    max_iterations = d["max_iterations"],
    inner_iterations = d["inner_iterations"],
)
hashes=PaperRebuild.r4_science_hashes()
source_commit=readchomp(`git -C $root rev-parse HEAD`)
worktree_status=readchomp(`git -C $root status --short`)
mkpath(dest)
records=Dict{String,Any}[]
optimizers=Dict(which=>r4_optimizer(Symbol(which)) for which in unique(x.solver for x in jobs))
for job in jobs
    c=cases[job.name]
    optimizer=optimizers[job.solver]
    modes=d["patterns"][job.pattern]
    purpose=Symbol(job.purpose)
    id=job.name*"--p"*string(job.pattern)*"--"*job.purpose*"--"*job.solver
    r=solve_r4_distributed(c; optimizer, modes, purpose, spec, budget_sec = d["budget_sec"])
    path=save_r4_distributed_run(c, r; directory = dest, run_id = id)
    read_r4_distributed_run(path)
    # 集中参考在分布法结束后才求解，禁止进入分布初始化、消息或候选选择。
    ref=PaperRebuild.r4_solve_stage(
        c,
        R4Spec(),
        optimizer,
        time()+d["budget_sec"];
        stage = purpose==:swm ? :central : :trading,
        build_options = (; modes),
    )
    ref["modes"]=modes
    ref["source_hashes_at_solve"]=hashes
    ref["validation"]=purpose==:swm ? validate_r4_solution(c, ref) : validate_r4_trading(c, ref)
    ref["schema"]="r4-distributed-reference-v1"
    reference=id*"--reference"
    save_r4_run(c, ref; directory = dest, run_id = reference)
    push!(
        records,
        Dict(
            "id"=>id,
            "reference"=>reference,
            "case"=>job.name,
            "pattern"=>job.pattern,
            "purpose"=>job.purpose,
            "solver"=>job.solver,
            "input_sha256"=>c.sha256,
        ),
    )
    println(id, " | ", r["status"], " | ", r["validation"])
    flush(stdout)
end
hashes==PaperRebuild.r4_science_hashes() || error("运行期间源码变化")
write(
    joinpath(dest, "study.toml"),
    PaperRebuild.r4_text(
        Dict(
            "records"=>records,
            "origin"=>"synthetic",
            "config_sha256"=>bytes2hex(sha256(read(config))),
            "source_hashes_at_solve"=>hashes,
            "source_commit"=>source_commit,
            "worktree_status_at_start"=>worktree_status,
        ),
    ),
)
hs=Dict{String,String}()
for (dir, _, files) in walkdir(dest), file in files
    path=joinpath(dir, file)
    hs[replace(relpath(path, dest), '\\'=>'/')]=bytes2hex(sha256(read(path)))
end
write(joinpath(dest, "batch-hashes.toml"), PaperRebuild.r4_text(Dict("sha256"=>hs)))
println("Saved ", dest)
