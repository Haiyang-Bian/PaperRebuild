include("r4_setup.jl")
using Dates, SHA
root=normpath(joinpath(@__DIR__, ".."))
config=joinpath(root, "configs", "r4", "reconfiguration", "study.toml")
d=TOML.parsefile(config)
batch=isempty(ARGS) ? "r4-network-"*Dates.format(now(), "yyyymmddTHHMMSS") : only(ARGS)
occursin(r"^[A-Za-z0-9_-]+$", batch) || error("非法批次名")
dest=joinpath(root, "results", "runs", "r4", batch)
ispath(dest) && error("不覆盖旧批次")
cases=Dict(
    name=>load_r4_case(joinpath(dirname(config), name*".toml")) for name in keys(d["input_sha256"])
)
all(cases[n].sha256==h for (n, h) in d["input_sha256"]) || error("冻结输入变化")
hashes=PaperRebuild.r4_science_hashes()
commit=readchomp(Cmd(["git", "-C", root, "rev-parse", "HEAD"]))
dirty=readchomp(Cmd(["git", "-C", root, "status", "--short"]))
records=Dict{String,Any}[]
mkpath(dest)
opt=r4_optimizer(:gurobi)
for name in d["cases"], policy in d["policies"], electric in d["electric_models"]
    c=cases[name]
    id=name*"--"*policy*"--"*electric
    println("BEGIN ", id)
    flush(stdout)
    r=solve_r4_reconfiguration(
        c;
        optimizer = opt,
        spec = R4ReconfigurationSpec(policy = Symbol(policy), electric = Symbol(electric)),
        budget_sec = d["budget_sec"],
    )
    path=save_r4_run(c, r; directory = dest, run_id = id)
    read_r4_run(path)
    push!(
        records,
        Dict(
            "id"=>id,
            "case"=>name,
            "policy"=>policy,
            "electric"=>electric,
            "input_sha256"=>c.sha256,
            "result_sha256"=>bytes2hex(sha256(read(joinpath(path, "result.toml")))),
        ),
    )
    println(
        id,
        " | ",
        r["status"],
        " | ",
        get(r, "operating_cost", NaN),
        " | model=",
        r["validation"]["model_pass"],
        " original=",
        r["validation"]["electric_original_pass"],
    )
    flush(stdout)
end
# 连续穷举与整数同输入参照完全独立，不向整数模型传入解或拓扑。
c=cases["oracle"]
oracle=enumerate_r4_reconfiguration(
    c;
    optimizer = r4_optimizer(:clarabel),
    budget_sec = d["budget_sec"],
)
op=save_r4_run(c, oracle; directory = dest, run_id = "oracle-enumeration")
validate_r4_network_enumeration(c, oracle)
read_r4_network_enumeration(op)
for electric in d["electric_models"]
    id="oracle--joint--"*electric
    r=solve_r4_reconfiguration(
        c;
        optimizer = opt,
        spec = R4ReconfigurationSpec(electric = Symbol(electric)),
        budget_sec = d["budget_sec"],
    )
    path=save_r4_run(c, r; directory = dest, run_id = id)
    read_r4_run(path)
    push!(
        records,
        Dict(
            "id"=>id,
            "case"=>"oracle",
            "policy"=>"joint",
            "electric"=>electric,
            "input_sha256"=>c.sha256,
            "result_sha256"=>bytes2hex(sha256(read(joinpath(path, "result.toml")))),
        ),
    )
end
hashes==PaperRebuild.r4_science_hashes() || error("科学源码变化")
manifest=Dict(
    "schema"=>"r4-network-study-v1",
    "batch_id"=>batch,
    "source_commit"=>commit,
    "initial_git_status"=>dirty,
    "config_sha256"=>bytes2hex(sha256(read(config))),
    "rules"=>d,
    "records"=>records,
    "oracle_result_sha256"=>bytes2hex(sha256(read(joinpath(op, "result.toml")))),
)
write(joinpath(dest, "study.toml"), PaperRebuild.r4_text(manifest))
println(
    "Finished ",
    length(records),
    " integer runs and ",
    length(oracle["records"]),
    " convex oracle records.",
)
