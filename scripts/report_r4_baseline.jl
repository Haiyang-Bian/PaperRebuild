# 保存值重新验收与成对比较；不引入优化器，不以失败为理由挑选输入。
using PaperRebuild, TOML, SHA, CSV
length(ARGS) in (1, 2) || error("参数：study.toml [新报告目录]")
root=normpath(joinpath(@__DIR__, ".."))
study_path=abspath(ARGS[1])
manifest=TOML.parsefile(study_path)
output=length(ARGS)==2 ? ARGS[2] : joinpath(root, "results", "summaries", "r4-baseline")
ispath(output) && error("不覆盖已有报告")
mkpath(output)
rows=NamedTuple[]
residuals=NamedTuple[]
actors=NamedTuple[]
flows=NamedTuple[]
runs=Dict{Tuple{String,String},Any}()
frozen_path=joinpath(root, "configs", "r4", "baseline", "study.toml")
manifest["study_sha256"]==bytes2hex(sha256(read(frozen_path))) || error("实验清单改变")
frozen=Dict(e["name"]=>e["sha256"] for e in TOML.parsefile(frozen_path)["case"])
length(manifest["runs"])==13 || error("本批要求12个方式及1个开放对照；未完成批次不作正式报告")
for entry in manifest["runs"]
    rr=read_r4_run(joinpath(dirname(study_path), entry["directory"]))
    c=rr.case
    c.sha256==frozen[entry["case"]] || error("未冻结输入")
    result=rr.result
    val=rr.validation
    key=(entry["case"], entry["variant"])
    haskey(runs, key) && error("重复运行")
    runs[key]=rr
    push!(
        rows,
        (
            case = entry["case"],
            variant = entry["variant"],
            run_id = result["run_id"],
            path = replace(
                relpath(joinpath(dirname(study_path), entry["directory"]), root),
                '\\'=>'/',
            ),
            input_sha256 = c.sha256,
            status = result["status"],
            model_pass = val["model_pass"],
            electric_original_pass = val["electric_original_pass"],
            heat_pass = val["heat_pass"],
            ledger_pass = val["ledger_pass"],
            cost = get(result, "operating_cost", NaN),
            bound = get(result, "objective_bound", NaN),
            gap = get(result, "relative_gap", NaN),
            cost_complete = result["cost_optimization_complete"],
            seconds = result["elapsed_sec"],
        ),
    )
    for x in val["rows"]
        push!(
            residuals,
            (
                run_id = result["run_id"],
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
    haskey(result, "ledger") || continue
    for x in result["ledger"]["actors"]
        push!(
            actors,
            (
                run_id = result["run_id"],
                actor = x["actor"],
                resource = x["resource"],
                external = x["external"],
                dissatisfaction = x["dissatisfaction"],
                prepayment_cost = x["prepayment_cost"],
                net_cash = x["internal_net_cash"],
                utility = x["utility"],
            ),
        )
    end
    for x in result["ledger"]["contracts"]
        push!(
            flows,
            (
                run_id = result["run_id"],
                actor = x["actor"],
                carrier = x["carrier"],
                t = x["t"],
                net_MW = x["net_MW"],
                peer_MW = x["peer_export_MW"],
            ),
        )
    end
end
pairs=Dict{String,Any}[]
for name in sort(collect(keys(frozen)))
    ag=runs[(name, "independent_exact")]
    sw=runs[(name, "central_exact")]
    comparison=r4_coordination_surplus(ag.case, ag.result, sw.result)
    comparison["case"]=name
    comparison["independent_run"]=ag.result["run_id"]
    comparison["central_run"]=sw.result["run_id"]
    push!(pairs, comparison)
end
function equivalent_except_flex(a, b)
    da=deepcopy(a.data)
    db=deepcopy(b.data)
    for d in (da, db)
        d["name"]="_"
        foreach(x->x["flex"]=0.0, d["actors"])
    end
    return da==db
end
effects=NamedTuple[]
for policy in ("open", "import")
    fixed=runs[(policy*"_fixed", "central_exact")]
    flex=runs[(policy*"_flexible", "central_exact")]
    equivalent_except_flex(fixed.case, flex.case) || error("flex对照存在混杂因素")
    qualified=all(
        rr.validation[k] for rr in (fixed, flex) for
        k in ("model_pass", "electric_original_pass", "heat_pass", "ledger_pass")
    )
    push!(
        effects,
        (
            policy,
            fixed_run = fixed.result["run_id"],
            flexible_run = flex.result["run_id"],
            same_preference_and_other_data = true,
            qualified,
            fixed_cost = get(fixed.result, "operating_cost", NaN),
            flexible_cost = get(flex.result, "operating_cost", NaN),
            candidate_saving = qualified ?
                               fixed.result["operating_cost"]-flex.result["operating_cost"] : NaN,
        ),
    )
end
gu=only(filter(x->x.case=="import_flexible"&&x.variant=="central_socp", rows))
cl=only(filter(x->x.variant=="clarabel_enumeration", rows))
delta=abs(gu.cost-cl.cost)/max(1, abs(gu.cost))
a2=Dict(
    "relative_cost_difference"=>delta,
    "gurobi_gap"=>gu.gap,
    "clarabel_gap"=>cl.gap,
    "pass"=>delta<=1e-4&&gu.gap<=1e-4&&cl.gap<=1e-4&&gu.model_pass&&cl.model_pass,
    "model"=>"same central SOCP; explicit preference; import-only; binary enumeration",
)
for (name, data) in (
    ("comparison", rows),
    ("residuals", residuals),
    ("actors", actors),
    ("contracts", flows),
    ("flexibility", effects),
)
    CSV.write(joinpath(output, name*".csv"), data)
end
write(joinpath(output, "surplus.toml"), PaperRebuild.r4_text(Dict("pairs"=>pairs)))
write(joinpath(output, "solver-comparison.toml"), PaperRebuild.r4_text(a2))
write(
    joinpath(output, "report.toml"),
    PaperRebuild.r4_text(
        Dict(
            "batch"=>manifest["batch"],
            "origin"=>"synthetic",
            "bargaining"=>"not_performed",
            "study_sha256"=>bytes2hex(sha256(read(study_path))),
            "frozen_study_sha256"=>manifest["study_sha256"],
            "script_sha256"=>bytes2hex(sha256(read(@__FILE__))),
            "thermal_scope"=>"static energy flow; no complete temperature field",
        ),
    ),
)
println("Report: ", abspath(output))
for p in pairs
    println(
        p["case"],
        " | eligible=",
        p["eligible"],
        " | saving=",
        get(p, "resource_saving", "none"),
    )
end
