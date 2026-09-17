include("r3_setup.jl")
using Clarabel
push!(LOAD_PATH, joinpath(@__DIR__, "..", "tools", "solvers"))
using Gurobi
cfgpath="configs/r3/baseline-study.toml"
cfg=TOML.parsefile(cfgpath)
resume=findfirst(a->startswith(a, "--resume="), ARGS)
requested=filter(a->!startswith(a, "--resume="), ARGS)
selected=isempty(requested) ? cfg["entries"] : [e for e in cfg["entries"] if e["id"] in requested]
isempty(selected) && error("未知实验ID")
factory=r3_gurobi_factory(Gurobi)
batch="r3-baseline-"*Dates.format(now(UTC), "yyyymmddTHHMMSS")*"-"*string(uuid4())[1:8]
root=joinpath("results", "runs", batch)
mkdir(root)
cp(cfgpath, joinpath(root, "frozen.toml"))
records=Dict{String,Any}[]
science=PaperRebuild.r2_science_hashes()
if !isnothing(resume)
    path=split(ARGS[resume], '='; limit = 2)[2]
    old=TOML.parsefile(path)
    old["config_sha256"]==bytes2hex(sha256(read(cfgpath))) || error("续跑配置不同")
    old["science_hashes"]==science || error("续跑科学源码不同，须独立批次")
    for record in old["runs"]
        row=deepcopy(record)
        row["directory"]=replace(
            relpath(normpath(joinpath(dirname(path), record["directory"])), root),
            '\\'=>'/',
        )
        read_r3_run(normpath(joinpath(root, row["directory"])))
        push!(records, row)
    end
    done=Set(x["id"] for x in records)
    selected=filter(e->!(e["id"] in done), selected)
end
function checkpoint()
    path=joinpath(root, "study.toml")
    temporary=path*".tmp"
    open(temporary, "w") do io
        TOML.print(
            io,
            Dict(
                "schema"=>"r3-baseline-study-v1",
                "batch"=>batch,
                "origin"=>"synthetic",
                "config_sha256"=>bytes2hex(sha256(read(cfgpath))),
                "science_hashes"=>science,
                "runs"=>records,
            );
            sorted = true,
        )
    end
    mv(temporary, path; force = true)
end
checkpoint()
println("BATCH ", root);
flush(stdout)
for e in selected
    PaperRebuild.r2_science_hashes()==science || error("正式批次科学源码改变")
    println("START ", e["id"])
    flush(stdout)
    c=load_r2_case(e["case_path"])
    c.sha256==e["input_sha256"] || error("输入改变")
    op=haskey(e, "operation") ? PaperRebuild.r3_operation_from_dict(e["operation"]) : nothing
    r=if e["method"]=="reference"
        solve_r3_reference(c; operation = op, optimizer = factory, budget_sec = cfg["budget_sec"])
    else
        solve_r3_baseline(
            c;
            operation = op,
            initial_flow = e["initial_flow"],
            spec = R3BaselineSpec(
                geometry = Symbol(e["geometry"]),
                initial_displacement = e["initial_displacement"],
            ),
            convex_optimizer = Clarabel.Optimizer,
            optimizer = factory,
            budget_sec = cfg["budget_sec"],
            max_iterations = cfg["max_iterations"],
        )
    end
    if e["method"]=="reference"
        # 直接参考也补查交付热量，保持本批物理核验口径一致。
        s=only(r["stages"])
        s["v3_physical_review"]=true
        v=validate_r3_solution(c, s)
        s["model_pass"], s["physics_pass"]=v.model_pass, v.physical_pass
        r["final_stage"]=v.physical_pass ? 1 : 0
        r["status"]=v.physical_pass ? "physical_feasible" : "no_verified_physical_solution"
        r["cost_optimization_complete"]=v.physical_pass && s["status"]=="solver_optimal"
    else
        r["initial_flow_sha256"]==e["initial_flow_sha256"] || error("初值改变")
    end
    r["parent_run_id"]=e["source_run_id"]
    r["parent_run_sha256"]=e["source_run_sha256"]
    path=save_r3_run(c, r; root, run_id = e["id"])
    loaded=read_r3_run(path)
    metrics=PaperRebuild.r3_baseline_row(loaded)
    row=merge(deepcopy(e), Dict(string(k)=>v for (k, v) in pairs(metrics)))
    row["directory"]=basename(path)
    push!(records, row)
    checkpoint()
    println(
        "DONE ",
        e["id"],
        " model=",
        row["model_cost"],
        " physical=",
        row["physical_pass"],
        " strict=",
        row["strict_redispatch_success"],
        " stop=",
        row["outer_status"],
    )
    flush(stdout)
    GC.gc()
end
println(joinpath(root, "study.toml"))
