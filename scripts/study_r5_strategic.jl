include("r5_strategic_setup.jl")
length(ARGS)==1||error("参数：新批次ID")
root=normpath(joinpath(@__DIR__, ".."))
id=only(ARGS)
occursin(r"^[A-Za-z0-9_-]+$", id)||error("批次ID错误")
output=joinpath(root, "results", "runs", id)
ispath(output)&&error("正式批次不覆盖")
config=joinpath(root, "configs", "r5", "strategic", "study.toml")
rules=TOML.parsefile(config)
for (file, hash) in rules["files"]
    bytes2hex(sha256(read(joinpath(dirname(config), file))))==hash||error("冻结策略输入改变")
end
factories=Dict(k=>r5_strategic_optimizer(Symbol(k)) for k in ("gurobi", "highs"))
mkpath(output)
study=Dict{String,Any}(
    "schema"=>"r5-strategic-study-v1",
    "batch_id"=>id,
    "source_commit"=>readchomp(Cmd(["git", "-C", root, "rev-parse", "HEAD"])),
    "config_sha256"=>bytes2hex(sha256(read(config))),
    "rules"=>rules,
    "records"=>Dict{String,Any}[],
    "complete"=>false,
    "source_sha256"=>PaperRebuild.r5_strategic_science_hashes(),
)
save() = write(joinpath(output, "study.toml"), PaperRebuild.r5_market_text(study))
save()
for spec in rules["runs"]
    c=load_r5_strategic_case(joinpath(dirname(config), spec["case"]))
    kwargs=haskey(spec, "complementarity_pattern") ?
           (; complementarity_pattern = spec["complementarity_pattern"]) : (;)
    println("START ", spec["id"])
    flush(stdout)
    r=solve_r5_strategic(
        c;
        optimizer = factories[spec["solver"]],
        oracle_optimizer = factories["highs"],
        budget_sec = spec["budget_sec"],
        kwargs...,
    )
    save_r5_strategic_run(c, r, joinpath(output, spec["id"]))
    e=merge(
        deepcopy(spec),
        Dict(
            "run_id"=>r["run_id"],
            "case_sha256"=>c.sha256,
            "result_sha256"=>bytes2hex(sha256(read(joinpath(output, spec["id"], "result.toml")))),
        ),
    )
    push!(study["records"], e)
    save()
    println(
        "END ",
        spec["id"],
        " ",
        r["status"],
        " model=",
        r["validation"]["model_pass"],
        " cost=",
        get(r["validation"], "worst_total_cost_USD", NaN),
        " certified=",
        r["cost_optimization_complete"],
    )
    flush(stdout)
end
study["settlement"]=Dict{String,Any}()
for e in rules["selection_cases"]
    path=joinpath(root, split(e["case"], '/')...)
    bytes2hex(sha256(read(path)))==e["sha256"]||error("原市场输入不同")
    c=load_r5_market_case(path)
    r=solve_r5_market(c; optimizer = factories["highs"], budget_sec = 60)
    range=r5_market_settlement_range(c, r; optimizer = factories["highs"], budget_sec = 60)
    witness=Dict("case"=>c.data, "parent"=>r, "range"=>range)
    write(joinpath(output, "settlement-"*e["id"]*".toml"), PaperRebuild.r5_market_text(witness))
    study["settlement"][e["id"]]=bytes2hex(
        sha256(read(joinpath(output, "settlement-"*e["id"]*".toml"))),
    )
    save()
end
study["complete"]=true
save()
println("Study complete; all outcomes retained.")
