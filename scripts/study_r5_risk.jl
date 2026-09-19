include("r5_risk_setup.jl")
root=normpath(joinpath(@__DIR__, ".."))
config=joinpath(root, "configs", "r5", "risk", "study.toml")
rules=TOML.parsefile(config)
batch=isempty(ARGS) ? "r5-risk-"*Dates.format(now(), "yyyymmddTHHMMSS") : only(ARGS)
occursin(r"^[A-Za-z0-9_-]+$", batch)||error("风险批次名错误")
dest=joinpath(root, "results", "runs", "r5", batch)
ispath(dest)&&error("不覆盖风险批次；先核查原进程是否终止")
cases=Dict{String,R5RiskCase}()
for (file, hash) in rules["files"]
    path=joinpath(dirname(config), file)
    bytes2hex(sha256(read(path)))==hash||error("冻结风险输入变化")
    cases[file]=load_r5_risk_case(path)
end
science=PaperRebuild.r5_risk_science_hashes()
manifest=Dict{String,Any}(
    "schema"=>"r5-risk-study-v1",
    "batch_id"=>batch,
    "rules"=>rules,
    "config_sha256"=>bytes2hex(sha256(read(config))),
    "complete"=>false,
    "records"=>Dict{String,Any}[],
    "source_commit"=>readchomp(`git -C $root rev-parse HEAD`),
    "initial_git_status"=>read(`git -C $root status --short`, String),
    "oracle_solver"=>"clarabel",
    "solver_setup_sec"=>Dict{String,Any}(),
    "budget_scope"=>"Per method includes build, branches and independent transport certificates; common engine setup is separately timed. No end-to-end speed claim.",
)
mkpath(joinpath(dest, "producer"))
producer=Dict{String,String}()
for file in (
    "study_r5_risk.jl",
    "r5_risk_setup.jl",
    "r5_market_setup.jl",
    "freeze_r5_risk.jl",
    "r5_risk_cases.jl",
)
    path=joinpath(@__DIR__, file)
    cp(path, joinpath(dest, "producer", file))
    producer[file]=bytes2hex(sha256(read(path)))
end
manifest["producer_sha256"]=producer
function checkpoint_risk()
    path=joinpath(dest, "study.pending.toml")
    write(path, PaperRebuild.r5_market_text(manifest))
    mv(path, joinpath(dest, "study.toml"); force = true)
end
checkpoint_risk()
factories=Dict{String,Any}()
for solver in unique(x["solver"] for x in rules["runs"])
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
    r=Base.invokelatest(
        solve_r5_risk,
        c;
        optimizer = factories[entry["solver"]],
        oracle_optimizer = factories["clarabel"],
        method = Symbol(entry["method"]),
        budget_sec = rules["budget_sec"],
    )
    path=save_r5_risk_run(c, r, joinpath(dest, entry["id"]))
    read_r5_risk_run(path)
    record=deepcopy(entry)
    record["case_sha256"]=c.sha256
    record["result_sha256"]=bytes2hex(sha256(read(joinpath(path, "result.toml"))))
    push!(manifest["records"], record)
    checkpoint_risk()
    println(
        entry["id"],
        " | ",
        r["status"],
        " | model=",
        r["validation"]["model_pass"],
        " | risk=",
        r["validation"]["risk_pass"],
        " | cost=",
        r["cost_optimization_complete"],
    )
    flush(stdout)
end
science==PaperRebuild.r5_risk_science_hashes()||error("正式风险研究期间源码变化")
all(bytes2hex(sha256(read(joinpath(@__DIR__, f))))==h for (f, h) in producer)||error(
    "正式风险入口变化",
)
manifest["complete"]=true
checkpoint_risk()
