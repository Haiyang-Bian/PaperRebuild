# 已保存运行的只读比较，不调用优化器。
using PaperRebuild, TOML, SHA, CSV
length(ARGS) in (1, 2) || error("参数：study.toml [新报告目录]")
root=normpath(joinpath(@__DIR__, ".."))
study_path=abspath(ARGS[1]);
dir=dirname(study_path)
study=TOML.parsefile(study_path)
config=joinpath(root, "configs", "r4", "distributed-study.toml")
study["config_sha256"]==bytes2hex(sha256(read(config))) || error("冻结规则改变")
d=TOML.parsefile(config)
hashes=TOML.parsefile(joinpath(dir, "batch-hashes.toml"))["sha256"]
actual=Set{String}()
for (folder, _, files) in walkdir(dir), file in files
    rel=replace(relpath(joinpath(folder, file), dir), '\\'=>'/')
    rel=="batch-hashes.toml" || push!(actual, rel)
end
actual==Set(keys(hashes)) || error("批次文件清单改变")
for (rel, h) in hashes
    !isabspath(rel) && !(".." in split(rel, '/')) || error("非法存档路径")
    bytes2hex(sha256(read(joinpath(dir, rel))))==h || error("批次文件改变")
end
length(study["records"])==d["expected_distributed_runs"] || error("冻结运行缺失")
output=length(ARGS)==2 ? ARGS[2] : joinpath(root, "results", "summaries", "r4-distributed")
ispath(output) && error("不覆盖已有报告")
rows=NamedTuple[];
outer=NamedTuple[];
inner=NamedTuple[];
residuals=NamedTuple[];
contracts=NamedTuple[]
evidence=Dict{String,Any}[]
for entry in study["records"]
    loaded=read_r4_distributed_run(joinpath(dir, entry["id"]))
    c, r=loaded.case, loaded.result
    rp=joinpath(dir, entry["reference"])
    rc=load_r4_case(joinpath(rp, "input.toml"))
    ref=TOML.parsefile(joinpath(rp, "result.toml"))
    c.sha256==rc.sha256==entry["input_sha256"]==d["input_sha256"][entry["case"]] ||
        error("不同输入比较")
    r["modes"]==ref["modes"]==d["patterns"][entry["pattern"]] || error("不同离散模式比较")
    ref["spec"]["electric"]==r["spec"]["electric"]=="socp" || error("网络版本不同")
    purpose=entry["purpose"]
    purpose==r["purpose"] || error("目标不同")
    expected_stage=purpose=="swm" ? "central" : "trading"
    ref["stage"]==expected_stage || error("参考目标不同")
    rv=purpose=="swm" ? validate_r4_solution(c, ref) : validate_r4_trading(c, ref)
    isequal(rv, ref["validation"]) || error("参考验收改变")
    for rr in ref["solves"]
        rr["mode"]==join(r["modes"]) || error("集中参考没有固定同一模式")
    end
    cost=r["validation"]["operating_cost"]
    refcost=get(ref, "solver_objective", NaN)
    gap=get(ref, "relative_gap", NaN)
    delta=abs(cost-refcost)/max(1, abs(refcost))
    ref_pass=rv["model_pass"]&&isfinite(gap)&&gap<=d["reference_gap_tolerance"]
    push!(
        rows,
        (
            run_id = entry["id"],
            case = entry["case"],
            pattern = entry["pattern"],
            purpose,
            solver = entry["solver"],
            status = r["status"],
            outer_iterations = r["validation"]["outer_iterations"],
            inner_iterations = r["validation"]["inner_iterations"],
            consensus_A4 = r["validation"]["consensus_A4_pass"],
            model_A1 = r["validation"]["model_pass"],
            electric_original_A1 = r["validation"]["electric_original_pass"],
            cost,
            reference_cost = refcost,
            reference_bound = get(ref, "objective_bound", NaN),
            reference_gap = gap,
            reference_A2 = ref_pass,
            relative_cost_difference = delta,
            cost_A4 = ref_pass&&r["validation"]["model_pass"]&&delta<=d["cost_relative_tolerance"],
            elapsed_sec = r["elapsed_sec"],
            reference_elapsed_sec = ref["elapsed_sec"],
            input_sha256 = c.sha256,
            unit = "USD_synthetic",
        ),
    )
    for x in r["trace"]
        push!(
            outer,
            (
                run_id = entry["id"],
                case = entry["case"],
                pattern = entry["pattern"],
                solver = entry["solver"],
                iteration = x["iteration"],
                primal = x["primal"],
                dual = x["dual"],
                cost = x["candidate_cost"],
                reference_cost = refcost,
                model_A1 = x["model_pass"],
                electric_original_A1 = x["electric_original_pass"],
                elapsed_sec = x["elapsed_sec"],
            ),
        )
    end
    for x in r["inner_trace"]
        push!(
            inner,
            (
                run_id = entry["id"],
                purpose,
                outer_iteration = x["outer"],
                inner_iteration = x["iteration"],
                primal = x["primal"],
                dual = x["dual"],
                gap_A = x["block_gaps"][1],
                gap_B = x["block_gaps"][2],
            ),
        )
    end
    if haskey(r, "candidate")
        candidate=r["candidate"]
        for x in candidate["validation"]["rows"]
            push!(
                residuals,
                (
                    run_id = entry["id"],
                    purpose,
                    equation = x["equation"],
                    scope = x["scope"],
                    entity = x["entity"],
                    t = x["t"],
                    residual = x["residual"],
                    tolerance = x["tolerance"],
                    unit = x["unit"],
                    pass = x["pass"],
                ),
            )
        end
        for a in r["agents"], t in 1:c.data["T"], (k, carrier) in enumerate(("P", "H"))
            push!(
                contracts,
                (
                    run_id = entry["id"],
                    purpose,
                    actor = a["actor"],
                    carrier,
                    t,
                    peer_export_MW = a["peer"][k][t],
                ),
            )
        end
    end
    push!(
        evidence,
        Dict(
            "run_id"=>entry["id"],
            "source_result_sha256"=>bytes2hex(
                sha256(read(joinpath(dir, entry["id"], "result.toml"))),
            ),
            "reference_result_sha256"=>bytes2hex(sha256(read(joinpath(rp, "result.toml")))),
            "validation"=>r["validation"],
            "reference_validation"=>Dict(k=>v for (k, v) in rv if k!="rows"),
            "options"=>r["options"],
            "scales"=>r["scales"],
            "modes"=>r["modes"],
        ),
    )
end
mkpath(output)
for (file, data) in (
    ("comparison", rows),
    ("outer", outer),
    ("inner", inner),
    ("residuals", residuals),
    ("contracts", contracts),
)
    CSV.write(joinpath(output, file*".csv"), data)
end
write(joinpath(output, "evidence.toml"), PaperRebuild.r4_text(Dict("records"=>evidence)))
write(
    joinpath(output, "report.toml"),
    PaperRebuild.r4_text(
        Dict(
            "origin"=>"synthetic",
            "batch"=>basename(dir),
            "source_study_sha256"=>bytes2hex(sha256(read(study_path))),
            "source_hashes_at_solve"=>study["source_hashes_at_solve"],
            "config_sha256"=>study["config_sha256"],
            "script_sha256"=>bytes2hex(sha256(read(@__FILE__))),
            "distributed_runs"=>length(rows),
            "reference_runs"=>length(rows),
            "mode_scope"=>"fixed battery patterns, SOCP and steady energy flow",
            "physical_pass_scope"=>"electric_original_A1 applies only to SWM; AGNB has no network",
        ),
    ),
)
println(output)
