include("r5_market_setup.jl")
root=normpath(joinpath(@__DIR__, ".."))
config=joinpath(root, "configs", "r5", "market", "study.toml")
rules=TOML.parsefile(config)
batch=isempty(ARGS) ? "r5-market-"*Dates.format(now(), "yyyymmddTHHMMSS") : only(ARGS)
occursin(r"^[A-Za-z0-9_-]+$", batch)||error("批次名错误")
dest=joinpath(root, "results", "runs", "r5", batch)
ispath(dest)&&error("不覆盖市场批次；先检查旧进程与证据")
cases=Dict(
    name=>load_r5_market_case(joinpath(dirname(config), name*".toml")) for
    name in keys(rules["input_sha256"])
)
all(cases[name].sha256==hash for (name, hash) in rules["input_sha256"])||error("冻结案例变化")
hashes=PaperRebuild.r5_market_science_hashes()
manifest=Dict{String,Any}(
    "schema"=>"r5-market-study-v1",
    "batch_id"=>batch,
    "rules"=>rules,
    "config_sha256"=>bytes2hex(sha256(read(config))),
    "records"=>Dict{String,Any}[],
    "complete"=>false,
    "source_commit"=>readchomp(`git -C $root rev-parse HEAD`),
    "initial_git_status"=>read(`git -C $root status --short`, String),
)
mkpath(dest)
mkpath(joinpath(dest, "producer"))
producer=Dict{String,String}()
for file in
    ("study_r5_market.jl", "r5_market_setup.jl", "freeze_r5_market.jl", "r5_market_cases.jl")
    path=joinpath(@__DIR__, file)
    cp(path, joinpath(dest, "producer", file))
    producer[file]=bytes2hex(sha256(read(path)))
end
manifest["producer_sha256"]=producer
function checkpoint()
    path=joinpath(dest, "study.pending.toml")
    write(path, PaperRebuild.r5_market_text(manifest))
    mv(path, joinpath(dest, "study.toml"); force = true)
end
checkpoint()
factories=Dict{String,Any}()
for solver in unique(x["solver"] for x in rules["records"])
    factories[solver]=try
        r5_market_optimizer(Symbol(solver))
    catch err
        # 环境构造失败仍交给运行接口保存状态，不漏掉预先冻结的记录。
        let cause=err
            ()->throw(cause)
        end
    end
end
for entry in rules["records"]
    println("BEGIN ", entry["id"])
    flush(stdout)
    c=cases[entry["case"]]
    start=time()
    optimizer=factories[entry["solver"]]
    r=Base.invokelatest(solve_r5_market, c; optimizer, budget_sec = rules["budget_sec"])
    certificate=Dict{String,Any}("status"=>"not_attempted_without_primal", "verified"=>false)
    if haskey(r, "values")
        try
            remaining=rules["budget_sec"]-(time()-start)
            if remaining>0
                dual=Base.invokelatest(build_r5_market_dual, c; optimizer)
                remaining=rules["budget_sec"]-(time()-start)
                if remaining>0
                    set_silent(dual.model)
                    set_time_limit_sec(dual.model, remaining)
                    optimize!(dual.model)
                    certificate["status"]=string(termination_status(dual.model))
                    if primal_status(dual.model) in (MOI.FEASIBLE_POINT, MOI.NEARLY_FEASIBLE_POINT)
                        certificate["objective"]=objective_value(dual.model)
                        certificate["multipliers"]=Dict(
                            string(k)=>(
                                ndims(v)==1 ? collect(value.(v)) :
                                PaperRebuild.r5_market_rows(value.(v))
                            ) for (k, v) in dual.variables
                        )
                        trial=deepcopy(r)
                        trial["multipliers"]=certificate["multipliers"]
                        delete!(trial, "raw_duals")
                        delete!(trial, "lower_bound_duals")
                        check=validate_r5_market(c, trial)
                        certificate["dual_value_recomputed"]=check["dual_value"]
                        certificate["relative_gap"]=check["relative_gap"]
                        certificate["verified"]=all(x["pass"] for x in check["rows"]) &&
                                                abs(check["dual_value"]-certificate["objective"])<=1e-6*max(
                            1.0,
                            abs(certificate["objective"]),
                        )
                    end
                else
                    certificate["status"]="budget_exhausted_in_build"
                end
            else
                certificate["status"]="budget_exhausted"
            end
        catch err
            certificate["status"]="execution_error"
            certificate["error"]=sprint(showerror, err)
        end
    end
    r["independent_dual"]=certificate
    r["total_method_elapsed_sec"]=time()-start
    path=save_r5_market_run(c, r, joinpath(dest, entry["id"]))
    read_r5_market_run(path)
    item=deepcopy(entry)
    item["case_sha256"]=c.sha256
    item["result_sha256"]=bytes2hex(sha256(read(joinpath(path, "result.toml"))))
    push!(manifest["records"], item)
    checkpoint()
    println(
        entry["id"],
        " | ",
        r["status"],
        " | primal/KKT=",
        r["validation"]["model_pass"],
        "/",
        r["validation"]["kkt_pass"],
        " | dual=",
        certificate["verified"],
    )
    flush(stdout)
end
hashes==PaperRebuild.r5_market_science_hashes()||error("市场研究期间源码变化")
all(bytes2hex(sha256(read(joinpath(@__DIR__, file))))==hash for (file, hash) in producer)||error(
    "实验入口发生变化",
)
manifest["complete"]=true;
checkpoint()
