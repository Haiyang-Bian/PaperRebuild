# 补证与分配分开：旧分歧点及物理调度不变，新运行只提供同局部模型的有效界。
include("r4_setup.jl")
using SHA, Dates
root=normpath(joinpath(@__DIR__, ".."))
config=joinpath(root, "configs", "r4", "bargaining-study.toml")
spec=TOML.parsefile(config)
batch=isempty(ARGS) ? "r4-bargaining-"*Dates.format(now(), "yyyymmddTHHMMSS") : only(ARGS)
occursin(r"^[A-Za-z0-9_-]+$", batch) || error("非法批次名")
dest=joinpath(root, "results", "runs", "r4", batch)
ispath(dest) && error("不覆盖已有批次")
mkpath(dest)
hashes=PaperRebuild.r4_science_hashes()
certificates=Dict{String,Any}[]
allocations=Dict{String,Any}[]
parents=joinpath(root, spec["parent_directory"])
for name in spec["cases"]
    agpath=joinpath(parents, name*"--independent_exact")
    swpath=joinpath(parents, name*"--central_exact")
    ag=read_r4_run(agpath)
    sw=read_r4_run(swpath)
    c=ag.case
    c.sha256==spec["input_sha256"][name] || error("父输入与冻结清单不一致")
    comparison=r4_coordination_surplus(c, ag.result, sw.result)
    comparison["eligible"] || error("父计划未通过独立物理验收")
    # 本地问题没有电网，故SOCP/原等式标签不影响其可行域；网络新解不替换父计划。
    cert=solve_r4_case(
        c;
        spec = R4Spec(operation = :independent, electric = :socp),
        optimizer = r4_optimizer(:clarabel),
        enumerate_battery = true,
        budget_sec = spec["budget_sec_per_certificate"],
    )
    certid=name*"--clarabel_certificate"
    path=save_r4_run(c, cert; directory = dest, run_id = certid)
    read_r4_run(path)
    rows=Dict{String,Any}[]
    for old in ag.result["local_stages"]
        matching=filter(x->x["actor"]==old["actor"], cert["local_stages"])
        row=Dict{String,Any}(
            "actor"=>c.data["actors"][old["actor"]]["id"],
            "historical_objective"=>old["solver_objective"],
            "historical_cost_complete"=>old["cost_optimization_complete"],
            "same_local_model"=>true,
            "certificate_pass"=>false,
        )
        if length(matching)==1
            check=only(matching)
            row["new_status"]=check["status"]
            row["new_model_pass"]=check["validation"]["model_pass"]
            row["new_cost_complete"]=check["cost_optimization_complete"]
            if haskey(check, "objective_bound") && haskey(check, "solver_objective")
                lower=check["objective_bound"]
                candidate=old["solver_objective"]
                delta=candidate-lower
                tol=1e-6*max(1.0, abs(candidate), abs(lower))
                row["new_objective"]=check["solver_objective"]
                row["new_lower_bound"]=lower
                row["historical_candidate_gap"]=delta/max(1.0, abs(candidate))
                row["new_gap"]=check["relative_gap"]
                row["certificate_pass"]=check["validation"]["model_pass"] &&
                                        check["cost_optimization_complete"] &&
                                        delta>=-tol &&
                                        abs(row["historical_candidate_gap"])<=spec["relative_certificate_tolerance"]
            end
        end
        push!(rows, row)
    end
    certificate=Dict(
        "case"=>name,
        "input_sha256"=>c.sha256,
        "run"=>certid,
        "parent_independent"=>name*"--independent_exact",
        "local_stages"=>rows,
        "local_certificate_pass"=>length(rows)==2&&all(x["certificate_pass"] for x in rows),
        "historical_record_rewritten"=>false,
        "scope"=>"local independent optima only; network original candidate and bound retained",
    )
    push!(certificates, certificate)
    for rule in spec["weight_rules"]
        weights=r4_bargaining_weights(c; rule = Symbol(rule))
        r=r4_allocate_coordination(c, ag.result, sw.result; weights = weights["weights"])
        r["weights_evidence"]=weights
        r["case"]=name
        r["parent_independent"]=name*"--independent_exact"
        r["parent_central"]=name*"--central_exact"
        r["parent_result_sha256"]=Dict(
            "independent"=>bytes2hex(sha256(read(joinpath(agpath, "result.toml")))),
            "central"=>bytes2hex(sha256(read(joinpath(swpath, "result.toml")))),
        )
        id=name*"--"*rule
        file=id*".toml"
        write(joinpath(dest, file), PaperRebuild.r4_text(r))
        push!(allocations, Dict("id"=>id, "file"=>file, "case"=>name, "rule"=>rule))
        println(id, " | ", r["allocation"]["status"], " | gain=", r["allocation"]["gain"])
    end
    println(name, " | local certificate=", certificate["local_certificate_pass"])
    flush(stdout)
end
hashes==PaperRebuild.r4_science_hashes() || error("执行期间科学源码改变")
write(joinpath(dest, "certificates.toml"), PaperRebuild.r4_text(Dict("certificates"=>certificates)))
write(
    joinpath(dest, "study.toml"),
    PaperRebuild.r4_text(
        Dict(
            "batch"=>batch,
            "origin"=>"synthetic",
            "config_sha256"=>bytes2hex(sha256(read(config))),
            "parent_directory"=>spec["parent_directory"],
            "allocations"=>allocations,
            "source_hashes_at_solve"=>hashes,
        ),
    ),
)
allhashes=Dict{String,String}()
for (dir, _, files) in walkdir(dest), file in files
    path=joinpath(dir, file)
    allhashes[replace(relpath(path, dest), '\\'=>'/')]=bytes2hex(sha256(read(path)))
end
write(joinpath(dest, "batch-hashes.toml"), PaperRebuild.r4_text(Dict("sha256"=>allhashes)))
println("Saved: ", joinpath(dest, "study.toml"))
