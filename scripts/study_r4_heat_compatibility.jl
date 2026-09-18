include("r4_setup.jl")
using TOML, SHA, Dates
root=normpath(joinpath(@__DIR__, ".."))
config_path=joinpath(root, "configs", "r4", "heat-compatibility-study.toml")
config=TOML.parsefile(config_path)
batch=joinpath(root, config["parent_batch"])
bytes2hex(sha256(read(joinpath(batch, "study.toml"))))==config["parent_study_sha256"] ||
    error("父批次已改变")
id=isempty(ARGS) ? "r4-heat-"*Dates.format(now(), "yyyymmddTHHMMSS") : only(ARGS)
occursin(r"^[A-Za-z0-9_-]+$", id) || error("非法批次名")
output=joinpath(root, "results", "runs", "r4", id)
ispath(output) && error("拒绝覆盖批次")
mkpath(output)
commit=readchomp(Cmd(["git", "-C", root, "rev-parse", "HEAD"]))
dirty=readchomp(Cmd(["git", "-C", root, "status", "--short"]))
hashes=PaperRebuild.r4_science_hashes()
for rel in keys(hashes)
    dest=joinpath(output, "snapshot", rel)
    mkpath(dirname(dest))
    cp(joinpath(root, rel), dest)
end
opt=r4_optimizer(:gurobi);
lp=r4_optimizer(:clarabel)
records=Dict{String,Any}[]
for x in config["records"], band in config["bands"]
    path=joinpath(batch, x["id"])
    bytes2hex(sha256(read(joinpath(path, "result.toml"))))==x["result_sha256"] ||
        error("父结果变化")
    old=read_r4_run(path)
    c=old.case
    parent=old.result
    c.sha256==x["input_sha256"] || error("父输入变化")
    deadline=time()+config["budget_sec"]
    outcomes=Dict{String,String}()
    for (j, stage) in enumerate(config["stages"])
        fixed=startswith(stage, "fixed")
        level=endswith(stage, "envelope") ? :envelope : :mixing
        label=x["id"]*"--"*band["id"]*"--"*stage
        if level==:mixing &&
           get(outcomes, fixed ? "fixed_envelope" : "free_envelope", "")=="solver_infeasible"
            push!(
                records,
                Dict(
                    "id"=>label,
                    "parent"=>x["id"],
                    "band"=>band["id"],
                    "stage"=>stage,
                    "status"=>"necessary_condition_infeasible",
                    "saved"=>false,
                ),
            )
            continue
        end
        spec=R4HeatCompatibilitySpec(;
            level,
            fixed_mass = fixed,
            supply_K = Tuple(band["supply_K"]),
            return_K = Tuple(band["return_K"]),
        )
        run=Base.invokelatest(
            reconstruct_r4_heat,
            c,
            parent;
            spec,
            optimizer = level==:envelope ? lp : opt,
            budget_sec = config["stage_budget_sec"][j],
            deadline,
        )
        save_r4_heat_run(joinpath(output, label), c, parent, run)
        loaded=read_r4_heat_run(joinpath(output, label))
        outcomes[stage]=run["status"]
        push!(
            records,
            Dict(
                "id"=>label,
                "parent"=>x["id"],
                "band"=>band["id"],
                "stage"=>stage,
                "status"=>run["status"],
                "saved"=>true,
                "pass"=>loaded.validation["pass"],
                "sha256"=>bytes2hex(sha256(read(joinpath(output, label, "reconstruction.toml")))),
            ),
        )
        println(label, " => ", run["status"], " (", round(run["elapsed_sec"]; digits = 2), " s)")
        flush(stdout)
    end
end
write(
    joinpath(output, "study.toml"),
    PaperRebuild.r4_text(
        Dict(
            "source_commit"=>commit,
            "initial_git_status"=>dirty,
            "source_hashes"=>hashes,
            "schema"=>"r4-heat-study-results-v1",
            "batch_id"=>id,
            "origin"=>"synthetic",
            "config_sha256"=>bytes2hex(sha256(read(config_path))),
            "rules"=>config,
            "records"=>records,
        ),
    ),
)
println(output)
