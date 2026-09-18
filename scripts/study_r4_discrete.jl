include("r4_setup.jl")
using Dates, SHA
root=normpath(joinpath(@__DIR__, ".."))
config=joinpath(root, "configs", "r4", "discrete-study.toml")
d=TOML.parsefile(config)
batch=isempty(ARGS) ? "r4-discrete-"*Dates.format(now(), "yyyymmddTHHMMSS") : only(ARGS)
occursin(r"^[A-Za-z0-9_-]+$", batch) || error("非法批次名")
dest=joinpath(root, "results", "runs", "r4", batch)
ispath(dest) && error("不覆盖旧批次")
cases=Dict(
    name=>load_r4_case(joinpath(root, "configs", "r4", "baseline", name*".toml")) for
    name in d["cases"]
)
all(cases[n].sha256==d["input_sha256"][n] for n in d["cases"]) || error("冻结输入变化")
all(length(r4_battery_patterns(c))==d["expected_patterns"] for c in values(cases)) ||
    error("模式范围变化")
hashes=PaperRebuild.r4_science_hashes()
source_commit=readchomp(Cmd(["git", "-C", root, "rev-parse", "HEAD"]))
dirty=readchomp(Cmd(["git", "-C", root, "status", "--short"]))
spec=R4DistributedSpec(;
    (Symbol(k)=>d[k] for k in ("rho", "peer_rho", "max_iterations", "inner_iterations"))...,
)
opt=r4_optimizer(:clarabel)
gurobi=r4_optimizer(:gurobi)
records=Dict{String,Any}[]
mkpath(dest)
for name in d["cases"], method in d["methods"]
    c=cases[name]
    id=name*"--"*method
    if method in ("distributed", "central_enumeration")
        r=solve_r4_discrete(
            c;
            optimizer = opt,
            method = Symbol(method),
            budget_sec = d["budget_sec"],
            distributed_spec = spec,
        )
        path=save_r4_discrete_run(c, r; directory = dest, run_id = id)
        read_r4_discrete_run(path)
    else
        r=solve_r4_case(
            c;
            optimizer = gurobi,
            spec = R4Spec(electric = method=="central_exact" ? :exact : :socp),
            budget_sec = d["budget_sec"],
        )
        path=save_r4_run(c, r; directory = dest, run_id = id)
        read_r4_run(path)
    end
    push!(records, Dict("id"=>id, "case"=>name, "method"=>method, "input_sha256"=>c.sha256))
    println(
        id,
        " | ",
        r["status"],
        " | ",
        method in ("distributed", "central_enumeration") ? r["validation"]["best_model_cost"] :
        get(r, "operating_cost", NaN),
    )
    flush(stdout)
end
# 仅固定一个QCP停止参数作一次有界对照；不回写默认工厂，不把成功参考注入分布法。
for name in d["precision_cases"], profile in d["precision_profiles"]
    c=cases[name]
    factory=profile=="original" ? gurobi :
            optimizer_with_attributes(
        gurobi.optimizer_constructor,
        gurobi.params...,
        "BarQCPConvTol"=>1e-9,
    )
    probe=Model(factory)
    effective=Dict(
        k=>get_optimizer_attribute(probe, k) for
        k in ("BarQCPConvTol", "FeasibilityTol", "OptimalityTol", "MIPGap")
    )
    r=solve_r4_distributed(
        c;
        optimizer = factory,
        modes = d["precision_pattern"],
        spec,
        budget_sec = d["precision_budget_sec"],
    )
    r["precision_profile"]=profile
    r["effective_parameters"]=effective
    id=name*"--precision--"*profile
    path=save_r4_distributed_run(c, r; directory = dest, run_id = id)
    read_r4_distributed_run(path)
    push!(
        records,
        Dict("id"=>id, "case"=>name, "method"=>"precision_"*profile, "input_sha256"=>c.sha256),
    )
    println(id, " | ", r["status"])
    flush(stdout)
end
hashes==PaperRebuild.r4_science_hashes() || error("运行期间科学源码改变")
write(
    joinpath(dest, "study.toml"),
    PaperRebuild.r4_text(
        Dict(
            "records"=>records,
            "origin"=>"synthetic",
            "config_sha256"=>bytes2hex(sha256(read(config))),
            "source_commit"=>source_commit,
            "source_hashes_at_solve"=>hashes,
            "worktree_status"=>dirty,
        ),
    ),
)
hs=Dict{String,String}()
for (folder, _, files) in walkdir(dest), file in files
    path=joinpath(folder, file)
    hs[replace(relpath(path, dest), '\\'=>'/')]=bytes2hex(sha256(read(path)))
end
write(joinpath(dest, "batch-hashes.toml"), PaperRebuild.r4_text(Dict("sha256"=>hs)))
println("Saved ", dest)
