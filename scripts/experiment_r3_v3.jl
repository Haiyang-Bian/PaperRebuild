include("r3_setup.jl")
using Clarabel
push!(LOAD_PATH, joinpath(@__DIR__, "..", "tools", "solvers"))
using Gurobi
cfgpath="configs/r3/v3-study.toml"
cfg=TOML.parsefile(cfgpath);
factory=r3_gurobi_factory(Gurobi)
selected=isempty(ARGS) ? cfg["entries"] : [e for e in cfg["entries"] if e["id"] in ARGS]
isempty(selected) && error("未知运行ID")
batch="r3-v3-"*Dates.format(now(UTC), "yyyymmddTHHMMSS")*"-"*string(uuid4())[1:8]
root=joinpath("results", "runs", batch);
mkdir(root);
cp(cfgpath, joinpath(root, "frozen.toml"))
records=Dict{String,Any}[]
function checkpoint()
    open(
        io->TOML.print(
            io,
            Dict(
                "batch"=>batch,
                "schema"=>"r3-v3-study-v1",
                "origin"=>"synthetic",
                "runs"=>records,
                "config_sha256"=>bytes2hex(sha256(read(cfgpath))),
            );
            sorted = true,
        ),
        joinpath(root, "study.toml"),
        "w",
    )
end
checkpoint()
for e in selected
    println("START ", e["id"])
    flush(stdout)
    c=load_r2_case(e["case_path"])
    c.sha256==e["input_sha256"] || error("输入改变")
    o=haskey(e, "mode") ? R3OperationSpec(c; mode = Symbol(e["mode"])) : nothing
    r=solve_r3_projected_gradient(
        c;
        algorithm = :r3_pg_checked_v3,
        operation = o,
        initial_flow = e["initial_flow"],
        optimizer = factory,
        convex_optimizer = Clarabel.Optimizer,
        local_halfspace = get(e, "local_halfspace", true),
        physical_recovery = e["physical_recovery"],
        stationarity_check = e["stationarity_check"],
        budget_sec = cfg["budget_sec"],
        max_iterations = cfg["max_iterations"],
    )
    r["initial_flow_sha256"]==e["initial_flow_sha256"] || error("初值改变")
    r["parent_run_id"]=e["source_run_id"]
    r["parent_run_sha256"]=e["run_sha256"]
    path=save_r3_run(c, r; root, run_id = e["id"])
    v=validate_r3_solution(c, r)
    final=r["final_stage"]
    record=merge(
        deepcopy(e),
        Dict(
            "directory"=>basename(path),
            "physical_pass"=>v.physical_pass,
            "outer_status"=>r["outer_status"],
            "outer_converged"=>r["outer_converged"],
            "local_stationarity_checked"=>r["local_stationarity_checked"],
            "elapsed_sec"=>r["elapsed_sec"],
            "cost"=>final>0 ? r["stages"][final]["operating_cost"] : NaN,
        ),
    )
    push!(records, record)
    checkpoint()
    println(
        "DONE ",
        e["id"],
        " physical=",
        v.physical_pass,
        " outer=",
        r["outer_status"],
        " cost=",
        record["cost"],
    )
    flush(stdout)
    GC.gc()
end
println(joinpath(root, "study.toml"))
