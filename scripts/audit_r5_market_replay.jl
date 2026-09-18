using PaperRebuild, TOML, SHA
length(ARGS)==3 || error("参数：首轮study.toml 环境复核study.toml 新核查TOML")
left, right, out=ARGS
ispath(out) && error("不覆盖既有复核证据")
a, b=TOML.parsefile(left), TOML.parsefile(right)
all(x["complete"]&&x["schema"]=="r5-market-study-v1" for x in (a, b)) || error("批次未完成")
a["rules"]==b["rules"] && a["config_sha256"]==b["config_sha256"] || error("环境复核改变了冻结规则")
dicts=[Dict(x["id"]=>x for x in study["records"]) for study in (a, b)]
Set(keys(dicts[1]))==Set(keys(dicts[2])) || error("两批配置不相同")
rows=Dict{String,Any}[]
for id in sort!(collect(keys(dicts[1])))
    loaded=[read_r5_market_run(joinpath(dirname(path), id)) for path in (left, right)]
    aa, bb=loaded
    for (i, (path, record)) in enumerate(zip((left, right), (dicts[1][id], dicts[2][id])))
        bytes2hex(sha256(read(joinpath(dirname(path), id, "result.toml"))))==record["result_sha256"] ||
            error("运行变化")
        loaded[i].case.sha256==record["case_sha256"] || error("输入变化")
    end
    aa.case.sha256==bb.case.sha256 || error("案例改变")
    for rel in (
        "src/core/r5_market.jl",
        "src/formulations/r5_market.jl",
        "src/verification/r5_market.jl",
        "Project.toml",
        "Manifest.toml",
    )
        aa.result["source_hashes_at_solve"][rel]==bb.result["source_hashes_at_solve"][rel] ||
            error("环境复核改变了模型/验证器/根环境")
    end
    comp=compare_r5_market_runs(joinpath(dirname(left), id), joinpath(dirname(right), id))
    row=Dict{String,Any}(
        "record_id"=>id,
        "case_sha256"=>aa.case.sha256,
        "old_run_id"=>aa.result["run_id"],
        "new_run_id"=>bb.result["run_id"],
        "old_status"=>aa.result["status"],
        "new_status"=>bb.result["status"],
        "old_optimality_pass"=>aa.validation["optimality_pass"],
        "new_optimality_pass"=>bb.validation["optimality_pass"],
        "old_result_sha256"=>dicts[1][id]["result_sha256"],
        "new_result_sha256"=>dicts[2][id]["result_sha256"],
        "same_model_comparison"=>comp,
        "new_solver_version"=>get(bb.result, "solver_version", "unavailable"),
    )
    if aa.validation["optimality_pass"]
        comp["A2_pass"] || error("已合格结果在复核中改变目标或丢失认证")
    end
    push!(rows, row)
end
result=Dict(
    "schema"=>"r5-market-environment-replay-v1",
    "origin"=>"synthetic",
    "old_batch"=>a["batch_id"],
    "new_batch"=>b["batch_id"],
    "old_study_sha256"=>bytes2hex(sha256(read(left))),
    "new_study_sha256"=>bytes2hex(sha256(read(right))),
    "config_sha256"=>a["config_sha256"],
    "rules_unchanged"=>true,
    "model_and_validator_unchanged"=>true,
    "scope"=>"Loader and engine/environment metadata fix; original statuses preserved. No scientific acceptance threshold change.",
    "records"=>rows,
    "script_sha256"=>bytes2hex(sha256(read(@__FILE__))),
)
mkpath(dirname(abspath(out)))
write(out, PaperRebuild.r5_market_text(result))
println(
    "Environment replay: ",
    length(rows),
    " paired inputs; model/validator/root environment unchanged; old successful objectives retained.",
)
