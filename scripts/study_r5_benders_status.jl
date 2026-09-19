include("r5_risk_setup.jl")
include("r5_benders_status_rules.jl")
root=normpath(joinpath(@__DIR__, ".."))
config=joinpath(root, "configs", "r5", "benders", "status-study.toml")
input=r5_benders_status_inputs(config)
rules=input.rules
batch=isempty(ARGS) ? "r5-benders-status-"*Dates.format(now(), "yyyymmddTHHMMSS") : only(ARGS)
occursin(r"^[A-Za-z0-9_-]+$", batch)||error("批次名非法")
dest=joinpath(root, "results", "runs", "r5", batch)
ispath(dest)&&error("不覆盖状态复核批次")
manifest=Dict{String,Any}(
    "schema"=>"r5-benders-status-study-v1",
    "batch_id"=>batch,
    "rules"=>rules,
    "config_sha256"=>bytes2hex(sha256(read(config))),
    "complete"=>false,
    "source_commit"=>readchomp(`git -C $root rev-parse HEAD`),
    "initial_git_status"=>read(`git -C $root status --short`, String),
    "probes"=>Dict{String,Any}[],
    "records"=>Dict{String,Any}[],
)
mkpath(joinpath(dest, "producer"))
producers=Dict{String,String}()
for f in (
    "study_r5_benders_status.jl",
    "r5_benders_status_rules.jl",
    "r5_benders_study_rules.jl",
    "r5_risk_setup.jl",
    "r5_market_setup.jl",
)
    cp(joinpath(@__DIR__, f), joinpath(dest, "producer", f))
    producers[f]=bytes2hex(sha256(read(joinpath(@__DIR__, f))))
end
manifest["producer_sha256"]=producers
function status_checkpoint()
    pending=joinpath(dest, "study.pending.toml")
    write(pending, PaperRebuild.r5_market_text(manifest))
    mv(pending, joinpath(dest, "study.toml"); force = true)
end
status_checkpoint()
tick=time()
base=r5_risk_optimizer(:gurobi)
factories=Dict(
    v=>optimizer_with_attributes(base.optimizer_constructor, base.params..., "DualReductions"=>v)
    for v in rules["probe_values"]
)
oracle=r5_risk_optimizer(:clarabel)
manifest["solver_setup_sec"]=time()-tick
manifest["requested_parameters"]=Dict(
    string(v)=>Dict(a.name=>b for (a, b) in f.params) for (v, f) in factories
)
# 新建模型避免复用前一次预处理/基；读取实际参数，再进入预声明的运行。
manifest["effective_DualReductions"]=Dict{String,Any}()
for (v, f) in factories
    model=Base.invokelatest(MOI.instantiate, f)
    actual=Base.invokelatest(MOI.get, model, MOI.RawOptimizerAttribute("DualReductions"))
    actual==v||error("实际DualReductions不同")
    manifest["effective_DualReductions"][string(v)]=actual
end
status_checkpoint()
for p in rules["probes"]
    println("PROBE ", p["id"])
    flush(stdout)
    c=input.cases[p["case"]]
    old=input.sources[p["source_id"]]
    start=time()
    deadline=start+rules["probe_budget_sec"]
    r=Dict{String,Any}(
        "entry"=>p,
        "results"=>Dict{String,Any}(),
        "source"=>old,
        "case"=>c.data,
        "case_sha256"=>c.sha256,
    )
    bounds=PaperRebuild.r5_benders_bounds(c, p["scenario"])
    r["bounded_objective"]=Dict(
        "lower"=>bounds.lower_cost,
        "upper"=>bounds.upper_cost,
        "finite_box"=>all(isfinite(l)&&isfinite(u) for (l, u) in values(bounds.box)),
    )
    for v in rules["probe_values"]
        remaining=deadline-time()
        remaining>0||break
        r["results"][string(v)]=Base.invokelatest(
            solve_r5_benders_subproblem,
            c,
            p["scenario"],
            old["first_stage"];
            branch = p["branch"],
            optimizer = factories[v],
            budget_sec = remaining,
            deadline,
        )
    end
    if haskey(r["results"], "0")&&r["results"]["0"]["status"]=="solver_infeasible"&&time()<deadline
        r["diagnostic"]=Base.invokelatest(
            solve_r5_benders_subproblem,
            c,
            p["scenario"],
            old["first_stage"];
            branch = p["branch"],
            elastic = true,
            optimizer = factories[0],
            budget_sec = deadline-time(),
            deadline,
            numerical_scale = input.original_rules["spec"]["diagnostic_scale"],
        )
    end
    r["elapsed_sec"]=time()-start
    r["budget_overrun_sec"]=max(0.0, time()-deadline)
    rel="probes/"*p["id"]*".toml"
    path=joinpath(dest, split(rel, '/')...)
    mkpath(dirname(path))
    write(path, PaperRebuild.r5_market_text(r))
    push!(
        manifest["probes"],
        Dict("id"=>p["id"], "file"=>rel, "sha256"=>bytes2hex(sha256(read(path)))),
    )
    status_checkpoint()
    println("  ", Dict(k=>v["status"] for (k, v) in r["results"]))
    flush(stdout)
end
for e in rules["runs"]
    println("METHOD ", e["id"])
    flush(stdout)
    c=input.cases[e["case"]]
    spec=r5_benders_study_spec(input.original_rules, Dict("route"=>"critical"))
    r=Base.invokelatest(
        solve_r5_benders,
        c;
        optimizer = factories[1],
        subproblem_optimizer = factories[0],
        oracle_optimizer = oracle,
        spec,
        budget_sec = rules["method_budget_sec"],
    )
    tick=time()
    path=save_r5_benders_run(c, r, joinpath(dest, e["id"]))
    read_r5_benders_run(path)
    rec=deepcopy(e)
    rec["case_sha256"]=c.sha256
    rec["result_sha256"]=bytes2hex(sha256(read(joinpath(path, "result.toml"))))
    rec["archive_verify_sec"]=time()-tick
    push!(manifest["records"], rec)
    status_checkpoint()
    println(
        "  ",
        r["status"],
        " | candidate=",
        r["validation"]["model_pass"],
        " | complete=",
        r["cost_optimization_complete"],
        " | iterations=",
        length(r["iterations"]),
    )
    flush(stdout)
end
r5_benders_status_inputs(config)
all(bytes2hex(sha256(read(joinpath(@__DIR__, f))))==h for (f, h) in producers)||error(
    "执行入口变化",
)
manifest["complete"]=true;
status_checkpoint()
println("Status study complete; original runs unchanged.")
