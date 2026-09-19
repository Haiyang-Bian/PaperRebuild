include("r5_risk_setup.jl")
include("r5_benders_study_rules.jl")
root=normpath(joinpath(@__DIR__, ".."))
config=joinpath(root, "configs", "r5", "benders", "study.toml")
input=r5_benders_study_inputs(config)
rules, cases=input.rules, input.cases
batch=isempty(ARGS) ? "r5-benders-"*Dates.format(now(), "yyyymmddTHHMMSS") : only(ARGS)
occursin(r"^[A-Za-z0-9_-]+$", batch)||error("分解批次名错误")
dest=joinpath(root, "results", "runs", "r5", batch)
ispath(dest)&&error("不覆盖分解批次；核查原进程后另建批次")
manifest=Dict{String,Any}(
    "schema"=>"r5-benders-study-v1",
    "batch_id"=>batch,
    "rules"=>rules,
    "config_sha256"=>bytes2hex(sha256(read(config))),
    "complete"=>false,
    "records"=>Dict{String,Any}[],
    "source_commit"=>readchomp(`git -C $root rev-parse HEAD`),
    "initial_git_status"=>read(`git -C $root status --short`, String),
    "solver_setup_sec"=>Dict{String,Any}(),
    "budget_scope"=>"Each full method includes model construction, all subproblems, transport oracles and validation. Setup and archive verification timed separately; no end-to-end speed comparison.",
)
mkpath(joinpath(dest, "producer"))
producer=Dict{String,String}()
for file in (
    "study_r5_benders.jl",
    "r5_benders_study_rules.jl",
    "r5_risk_setup.jl",
    "r5_market_setup.jl",
    "freeze_r5_benders.jl",
)
    path=joinpath(@__DIR__, file)
    cp(path, joinpath(dest, "producer", file))
    producer[file]=bytes2hex(sha256(read(path)))
end
manifest["producer_sha256"]=producer
function checkpoint_benders()
    path=joinpath(dest, "study.pending.toml")
    write(path, PaperRebuild.r5_market_text(manifest))
    mv(path, joinpath(dest, "study.toml"); force = true)
end
checkpoint_benders()
factories=Dict{String,Any}()
for solver in unique(vcat([e["solver"] for e in rules["runs"]], [rules["oracle_solver"]]))
    start=time()
    factories[solver]=try
        r5_risk_optimizer(Symbol(solver))
    catch err
        let cause=err
            ()->throw(cause)
        end
    end
    manifest["solver_setup_sec"][solver]=time()-start
end
for entry in rules["runs"]
    println("BEGIN ", entry["id"])
    flush(stdout)
    c=cases[entry["case"]]
    # 参考见证只在规则校验中检查哈希；算法只获得输入、求解器和已冻结规则。
    r=Base.invokelatest(
        solve_r5_benders,
        c;
        optimizer = factories[entry["solver"]],
        oracle_optimizer = factories[rules["oracle_solver"]],
        spec = r5_benders_study_spec(rules, entry),
        budget_sec = rules["budget_sec"],
    )
    tick=time()
    path=save_r5_benders_run(c, r, joinpath(dest, entry["id"]))
    read_r5_benders_run(path)
    record=deepcopy(entry)
    record["case_sha256"]=c.sha256
    record["result_sha256"]=bytes2hex(sha256(read(joinpath(path, "result.toml"))))
    record["archive_verify_sec"]=time()-tick
    push!(manifest["records"], record)
    checkpoint_benders()
    println(
        entry["id"],
        " | ",
        r["status"],
        " | candidate=",
        r["validation"]["model_pass"],
        " | full-cost=",
        r["cost_optimization_complete"],
        " | iterations=",
        length(r["iterations"]),
        " | seconds=",
        r["elapsed_sec"],
    )
    flush(stdout)
end
r5_benders_study_inputs(config)
all(bytes2hex(sha256(read(joinpath(@__DIR__, f))))==h for (f, h) in producer)||error(
    "分解执行入口改变",
)
manifest["complete"]=true
checkpoint_benders()
println("Frozen Benders study complete; failures retained.")
