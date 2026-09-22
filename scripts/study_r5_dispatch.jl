include("r5_market_setup.jl")
root=normpath(joinpath(@__DIR__, ".."))
config=joinpath(root, "configs", "r5", "dispatch", "study.toml");
rules=TOML.parsefile(config)
batch=isempty(ARGS) ? "r5-dispatch-"*Dates.format(now(), "yyyymmddTHHMMSS") : only(ARGS)
occursin(r"^[A-Za-z0-9_-]+$", batch)||error("批次名错误")
dest=joinpath(root, "results", "runs", "r5", batch)
ispath(dest)&&error("不覆盖既有IES批次，先核查原进程和状态")
cases=Dict(
    name=>load_r5_dispatch_case(joinpath(dirname(config), name*".toml")) for
    name in keys(rules["input_sha256"])
)
all(cases[name].sha256==hash for (name, hash) in rules["input_sha256"])||error("冻结输入变化")
hashes=PaperRebuild.r5_dispatch_science_hashes()
manifest=Dict{String,Any}(
    "schema"=>"r5-dispatch-study-v1",
    "batch_id"=>batch,
    "rules"=>rules,
    "config_sha256"=>bytes2hex(sha256(read(config))),
    "records"=>Dict{String,Any}[],
    "complete"=>false,
    "source_commit"=>readchomp(`git -C $root rev-parse HEAD`),
    "initial_git_status"=>read(`git -C $root status --short`, String),
)
mkpath(joinpath(dest, "producer"))
producer=Dict{String,String}()
for file in
    ("study_r5_dispatch.jl", "r5_market_setup.jl", "freeze_r5_dispatch.jl", "r5_dispatch_cases.jl")
    path=joinpath(@__DIR__, file)
    cp(path, joinpath(dest, "producer", file))
    producer[file]=bytes2hex(sha256(read(path)))
end
manifest["producer_sha256"]=producer
function checkpoint_dispatch()
    temp=joinpath(dest, "study.pending.toml")
    write(temp, PaperRebuild.r5_market_text(manifest))
    mv(temp, joinpath(dest, "study.toml"); force = true)
end
checkpoint_dispatch()
factories=Dict{String,Any}()
for solver in unique(x["solver"] for x in rules["records"])
    factories[solver]=try
        r5_market_optimizer(Symbol(solver))
    catch err
        let cause=err
            ()->throw(cause)
        end
    end
end
for entry in rules["records"]
    println("BEGIN ", entry["id"])
    flush(stdout)
    c=cases[entry["case"]]
    r=Base.invokelatest(
        solve_r5_dispatch,
        c;
        optimizer = factories[entry["solver"]],
        budget_sec = rules["budget_sec"],
    )
    path=save_r5_dispatch_run(c, r, joinpath(dest, entry["id"]))
    read_r5_dispatch_run(path)
    item=deepcopy(entry)
    item["case_sha256"]=c.sha256
    item["result_sha256"]=bytes2hex(sha256(read(joinpath(path, "result.toml"))))
    push!(manifest["records"], item)
    checkpoint_dispatch()
    println(
        entry["id"],
        " | ",
        r["status"],
        " | model=",
        r["validation"]["model_pass"],
        " | cost=",
        r["cost_optimization_complete"],
    )
    flush(stdout)
end
hashes==PaperRebuild.r5_dispatch_science_hashes()||error("研究期间IES源码变化")
all(bytes2hex(sha256(read(joinpath(@__DIR__, file))))==hash for (file, hash) in producer)||error(
    "实验入口变化",
)
manifest["complete"]=true;
checkpoint_dispatch()
