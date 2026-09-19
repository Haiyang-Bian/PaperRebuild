include("r5_strategic_setup.jl")
include("r5_strategic_benders_study_rules.jl")
root = normpath(joinpath(@__DIR__, ".."))
config = joinpath(root, "configs", "r5", "strategic-benders", "study.toml")
input = r5_sb_study_inputs(config)
rules = input.rules
batch =
    isempty(ARGS) ? "r5-strategic-benders-"*Dates.format(now(UTC), "yyyymmddTHHMMSS") : only(ARGS)
occursin(r"^[A-Za-z0-9_-]+$", batch) || error("批次编号非法")
dest = joinpath(root, "results", "runs", "r5", batch)
ispath(dest) && error("不覆盖批次；观察超时须先核查原进程")
manifest = Dict{String,Any}(
    "schema"=>"r5-strategic-benders-study-v1",
    "batch_id"=>batch,
    "rules"=>rules,
    "config_sha256"=>bytes2hex(sha256(read(config))),
    "complete"=>false,
    "source_commit"=>readchomp(`git -C $root rev-parse HEAD`),
    "initial_git_status"=>read(`git -C $root status --short`, String),
    "records"=>Dict{String,Any}[],
    "budget_scope"=>"Each full method includes modeling, nested solves and validation; loading and archive replay separately timed, no end-to-end speed claim.",
)
mkpath(joinpath(dest, "producer"))
for file in R5_SB_PRODUCERS
    cp(joinpath(@__DIR__, file), joinpath(dest, "producer", file))
end
function checkpoint_sb()
    p = joinpath(dest, "study.pending.toml")
    write(p, PaperRebuild.r5_market_text(manifest))
    mv(p, joinpath(dest, "study.toml"); force = true)
end
checkpoint_sb()
factories = Dict{String,Any}()
tick = time()
for name in ("gurobi", "highs")
    factories[name] = try
        r5_strategic_optimizer(Symbol(name))
    catch err
        let cause = err
            ()->throw(cause)
        end
    end
end
manifest["solver_setup_sec"] = time()-tick
for entry in rules["runs"]
    println("BEGIN ", entry["id"])
    flush(stdout)
    c = input.cases[entry["case"]]
    # 此调用不接收直接参考、参考分支或任何已求得策略。
    r = Base.invokelatest(
        solve_r5_strategic_benders,
        c;
        optimizer = factories[rules["master_solver"]],
        subproblem_optimizer = factories[rules["subproblem_solver"]],
        oracle_optimizer = factories[rules["oracle_solver"]],
        spec = r5_sb_study_spec(rules, entry),
        budget_sec = rules["budget_sec"],
    )
    tick = time()
    path = save_r5_strategic_benders_run(c, r, joinpath(dest, entry["id"]))
    read_r5_strategic_benders_run(path)
    record = deepcopy(entry)
    record["case_sha256"] = c.sha256
    record["result_sha256"] = bytes2hex(sha256(read(joinpath(path, "result.toml"))))
    record["archive_verify_sec"] = time()-tick
    push!(manifest["records"], record)
    checkpoint_sb()
    println(
        "END ",
        entry["id"],
        " | ",
        r["status"],
        " | full-cost=",
        r["cost_optimization_complete"],
        " | iterations=",
        length(r["iterations"]),
        " | seconds=",
        r["elapsed_sec"],
    )
    flush(stdout)
end
r5_sb_study_inputs(config)
manifest["complete"] = true
checkpoint_sb()
println("Strategy Benders formal study complete; failures and domain limits retained.")
