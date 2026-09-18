# 从已保存的主体数值拆分成本误差、末次共识和实际约束类型；不求解。
using PaperRebuild, TOML, CSV, SHA
length(ARGS)==2 || error("参数：study.toml 新报告目录")
study_path=abspath(ARGS[1]);
dir=dirname(study_path);
output=ARGS[2]
study=TOML.parsefile(study_path)
any(
    isfile(joinpath(output, x)) for
    x in ("audit.toml", "cost-closure.csv", "solver-blocks.csv", "failed-rows.csv")
) && error("不覆盖审计")
costrows=NamedTuple[];
blocks=NamedTuple[];
failures=NamedTuple[]
allowed=Set([
    "(AffExpr, MathOptInterface.EqualTo{Float64})",
    "(AffExpr, MathOptInterface.GreaterThan{Float64})",
    "(AffExpr, MathOptInterface.LessThan{Float64})",
    "(Vector{AffExpr}, MathOptInterface.SecondOrderCone)",
    "(Vector{AffExpr}, MathOptInterface.RotatedSecondOrderCone)",
    "(VariableRef, MathOptInterface.EqualTo{Float64})",
    "(VariableRef, MathOptInterface.GreaterThan{Float64})",
    "(VariableRef, MathOptInterface.LessThan{Float64})",
])
for entry in study["records"]
    loaded=read_r4_distributed_run(joinpath(dir, entry["id"]))
    c, r=loaded.case, loaded.result
    for key in ("agents", "last_attempt_agents")
        for a in get(r, key, Any[])
            all(x in allowed for x in get(a, "model_types", String[])) ||
                error("出现未核查模型类型")
            push!(
                blocks,
                (
                    run_id = entry["id"],
                    stage = key,
                    actor = a["actor"],
                    status = a["status"],
                    termination = get(a, "termination", "missing"),
                    augmented_objective = get(a, "augmented_objective", NaN),
                    augmented_gap = get(a, "augmented_relative_gap", NaN),
                    affine_and_soc_types_only = true,
                ),
            )
        end
    end
    for key in ("operator", "last_attempt_operator")
        haskey(r, key) || continue
        a=r[key]
        all(x in allowed for x in get(a, "model_types", String[])) || error("出现未核查网络类型")
        push!(
            blocks,
            (
                run_id = entry["id"],
                stage = key,
                actor = a["actor"],
                status = a["status"],
                termination = get(a, "termination", "missing"),
                augmented_objective = get(a, "augmented_objective", NaN),
                augmented_gap = get(a, "augmented_relative_gap", NaN),
                affine_and_soc_types_only = true,
            ),
        )
    end
    haskey(r, "candidate") || continue
    candidate=r["candidate"]
    for x in candidate["validation"]["rows"]
        x["pass"] && continue
        push!(
            failures,
            (
                run_id = entry["id"],
                equation = x["equation"],
                scope = x["scope"],
                entity = x["entity"],
                t = x["t"],
                residual = x["residual"],
                tolerance = x["tolerance"],
                ratio = x["residual"]/x["tolerance"],
                unit = x["unit"],
            ),
        )
    end
    cost_gap=candidate["solver_objective"]-candidate["operating_cost"]
    epigraph=0.0
    localfee=0.0
    for a in r["agents"]
        i=a["actor"]
        params=c.data["actors"][i]
        s=a["values"]
        for carrier in ("P", "H"), t in 1:c.data["T"]
            raw=s["w_"*carrier][i][t]
            multiplier=get(c.data, "preference_model", "")=="explicit_reference_v1" ? 1.0 :
                       params["sat_"*carrier]
            exact=params["sat_"*carrier]*(
                PaperRebuild.r4_preferred_demand(params, carrier, t)-s[carrier*"_D"][i][t]
            )^2
            epigraph+=c.data["dt_h"]*(multiplier*raw-exact)
            localfee+=c.data["dt_h"]*c.data["settlement"]["fee"]*s[carrier*"_fee_quantity"][t]
        end
    end
    if r["purpose"]=="swm"
        a=r["operator"]
        s=a["values"]
        params=c.data["actors"][1]
        for carrier in ("P", "H"), t in 1:c.data["T"]
            mult=get(c.data, "preference_model", "")=="explicit_reference_v1" ? 1.0 :
                 params["sat_"*carrier]
            epigraph+=c.data["dt_h"]*(
                mult*s["w_"*carrier][1][t]-params["sat_"*carrier]*(
                    PaperRebuild.r4_preferred_demand(params, carrier, t)-s[carrier*"_D"][1][t]
                )^2
            )
        end
        fee_difference=0.0
    else
        exactfee=c.data["dt_h"]*c.data["settlement"]["fee"]*sum(
            abs(x) for carrier in ("P", "H") for x in candidate["values"][carrier*"_peer"]
        )
        fee_difference=localfee-exactfee
    end
    decomposition_error=cost_gap-epigraph-fee_difference
    abs(decomposition_error)<=1e-8 || error("成本差分解不闭合")
    tail=isempty(r["inner_trace"]) ? nothing : last(r["inner_trace"])
    push!(
        costrows,
        (
            run_id = entry["id"],
            purpose = r["purpose"],
            cost_gap,
            epigraph_excess = epigraph,
            fee_excess_and_consensus = fee_difference,
            decomposition_error,
            last_inner_primal = tail===nothing ? NaN : tail["primal"],
            last_inner_dual = tail===nothing ? NaN : tail["dual"],
            unit = "USD_synthetic",
        ),
    )
end
CSV.write(joinpath(output, "cost-closure.csv"), costrows)
CSV.write(joinpath(output, "solver-blocks.csv"), blocks)
CSV.write(joinpath(output, "failed-rows.csv"), failures)
write(
    joinpath(output, "audit.toml"),
    PaperRebuild.r4_text(
        Dict(
            "script_sha256"=>bytes2hex(sha256(read(@__FILE__))),
            "source_study_sha256"=>bytes2hex(sha256(read(study_path))),
            "records"=>length(costrows),
            "all_recorded_block_constraints_affine_or_soc"=>true,
            "quadratic_objective_psd_basis"=>"positive rho times squared affine residuals",
            "cost_decomposition_tolerance"=>1e-8,
            "source_commit"=>study["source_commit"],
        ),
    ),
)
println("Cost closure and all recorded block constraint types independently audited.")
