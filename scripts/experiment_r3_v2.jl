push!(LOAD_PATH, normpath(joinpath(@__DIR__, "..")))
include("r3_setup.jl")
using Clarabel, Gurobi
cfgpath=joinpath("configs", "r3", "v2-study.toml")
cfg=TOML.parsefile(cfgpath)
factory=r3_gurobi_factory(Gurobi)
batch="r3-v2-"*Dates.format(now(UTC), "yyyymmddTHHMMSS")*"-"*string(uuid4())[1:8]
root=joinpath("results", "runs", batch);
mkdir(root)
cp(cfgpath, joinpath(root, "config.toml"))
prior=TOML.parsefile(cfg["prior_study"])
entries=Dict{String,Any}[]
for old in prior["runs"]
    push!(
        entries,
        Dict(
            "id"=>old["id"],
            "group"=>"robustness",
            "case"=>old["case"],
            "old_directory"=>joinpath(dirname(cfg["prior_study"]), old["directory"]),
        ),
    )
end
for name in cfg["cases"], mode in cfg["modes"], method in cfg["methods"]
    push!(
        entries,
        Dict(
            "id"=>name*"-"*mode*"-"*method,
            "group"=>"modes",
            "case"=>name,
            "mode"=>mode,
            "method"=>method,
        ),
    )
end
# 输入哈希与全部运行列表在任何本批优化之前冻结。
for e in entries
    path=e["group"]=="robustness" ? joinpath(e["old_directory"], "run.toml") :
         joinpath("configs", "r3", e["case"]*"-four-modes-v1.toml")
    e["frozen_source_sha256"]=bytes2hex(sha256(read(path)))
end
open(
    io->TOML.print(io, Dict("entries"=>entries, "config"=>cfg); sorted = true),
    joinpath(root, "frozen.toml"),
    "w",
)
records=Dict{String,Any}[]
function checkpoint()
    open(
        io->TOML.print(
            io,
            Dict(
                "batch"=>batch,
                "schema"=>"r3-v2-study-v1",
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
group_arg=findfirst(a->startswith(a, "--group="), ARGS)
group=isnothing(group_arg) ? "all" : split(ARGS[group_arg], '='; limit = 2)[2]
group in ("all", "robustness", "modes") || error("未知实验组")
selected=filter(a->!startswith(a, "--group="), ARGS)
all(id->any(e["id"]==id for e in entries), selected) || error("未知实验ID")
for entry in entries
    (group=="all" || entry["group"]==group) || continue
    isempty(selected)||entry["id"] in selected || continue
    println("START ", entry["id"])
    flush(stdout)
    if entry["group"]=="robustness"
        old=read_r3_run(entry["old_directory"])
        c=old.case
        initial=old.result["initial_flow"]
        r=solve_r3_projected_gradient(
            c;
            algorithm = :r3_pg_checked_v2,
            initial_flow = initial,
            local_halfspace = old.result["local_halfspace"],
            optimizer = factory,
            convex_optimizer = Clarabel.Optimizer,
            budget_sec = cfg["budget_sec"],
            max_iterations = cfg["max_iterations"],
        )
        r["parent_run_id"]=prior["batch"]*"/"*old.metadata["run_id"]
        r["initial_flow_sha256"]==old.result["initial_flow_sha256"] || error("初始流量发生变化")
    else
        c=load_r2_case(joinpath("configs", "r3", entry["case"]*"-four-modes-v1.toml"))
        operation=R3OperationSpec(c; mode = Symbol(entry["mode"]))
        r=entry["method"]=="pg" ?
          solve_r3_projected_gradient(
            c;
            algorithm = :r3_pg_checked_v2,
            operation,
            optimizer = factory,
            convex_optimizer = Clarabel.Optimizer,
            budget_sec = cfg["budget_sec"],
            max_iterations = cfg["max_iterations"],
        ) : solve_r3_reference(c; operation, optimizer = factory, budget_sec = cfg["budget_sec"])
    end
    path=save_r3_run(c, r; root, run_id = entry["id"])
    validation=read_r3_run(path).validation
    push!(
        records,
        merge(
            entry,
            Dict(
                "directory"=>entry["id"],
                "physical_pass"=>validation.physical_pass,
                "outer_status"=>r["outer_status"],
                "elapsed_sec"=>r["elapsed_sec"],
            ),
        ),
    )
    checkpoint()
    println(
        "DONE ",
        entry["id"],
        " physical=",
        validation.physical_pass,
        " stop=",
        r["outer_status"],
        " seconds=",
        round(r["elapsed_sec"]; digits = 2),
    )
    flush(stdout)
end
println(joinpath(root, "study.toml"))
