include("r4_setup.jl")
using Dates, SHA
root=normpath(joinpath(@__DIR__, ".."))
config=joinpath(root, "configs", "r4", "thermal-study.toml")
rules=TOML.parsefile(config)
batch=isempty(ARGS) ? "r4-thermal-"*Dates.format(now(), "yyyymmddTHHMMSS") : only(ARGS)
occursin(r"^[A-Za-z0-9_-]+$", batch) || error("非法批次名")
dest=joinpath(root, "results", "runs", "r4", batch)
ispath(dest) && error("不覆盖旧批次；未完成批次须先检查运行句柄和已有证据")
cases=Dict(
    n=>load_r4_case(joinpath(root, "configs", "r4", "reconfiguration", n*".toml")) for
    n in keys(rules["input_sha256"])
)
all(cases[n].sha256==h for (n, h) in rules["input_sha256"]) || error("冻结输入变化")
hashes=PaperRebuild.r4_science_hashes()
manifest=Dict{String,Any}(
    "schema"=>"r4-thermal-study-v1",
    "batch_id"=>batch,
    "source_commit"=>readchomp(Cmd(["git", "-C", root, "rev-parse", "HEAD"])),
    "initial_git_status"=>readchomp(Cmd(["git", "-C", root, "status", "--short"])),
    "config_sha256"=>bytes2hex(sha256(read(config))),
    "rules"=>rules,
    "records"=>Dict{String,Any}[],
    "complete"=>false,
)
mkpath(dest)
function checkpoint()
    temporary=joinpath(dest, "study.pending.toml")
    write(temporary, PaperRebuild.r4_text(manifest))
    mv(temporary, joinpath(dest, "study.toml"); force = true)
end
checkpoint()
optimizer=r4_optimizer(:gurobi)
for x in rules["records"]
    id=x["id"]
    println("BEGIN ", id)
    flush(stdout)
    c=cases[x["case"]]
    spec=R4ThermalSpec(
        policy = Symbol(x["policy"]),
        electric = Symbol(rules["electric"]),
        loss = Symbol(x["loss"]),
        supply_K = Tuple(rules["supply_K"]),
        return_K = Tuple(rules["return_K"]),
        flow_floor = rules["flow_floor"],
    )
    r=Base.invokelatest(solve_r4_thermal, c; spec, optimizer, budget_sec = rules["budget_sec"])
    path=save_r4_run(c, r; directory = dest, run_id = id)
    read_r4_run(path)
    row=deepcopy(x)
    row["input_sha256"]=c.sha256
    row["result_sha256"]=bytes2hex(sha256(read(joinpath(path, "result.toml"))))
    push!(manifest["records"], row)
    checkpoint()
    println(
        id,
        " | ",
        r["status"],
        " | ",
        get(r, "operating_cost", NaN),
        " | model=",
        r["validation"]["model_pass"],
        " electric=",
        r["validation"]["electric_original_pass"],
        " gap=",
        get(r, "relative_gap", NaN),
    )
    flush(stdout)
end
hashes==PaperRebuild.r4_science_hashes() || error("正式实验期间科学源码变化")
manifest["complete"]=true
checkpoint()
println("Finished ", length(manifest["records"]), " thermal runs. Failures retained.")
