# 读取既有证据，所有表格来自保存数值；本脚本不调用优化器。
include("r4_setup.jl")
using CSV
function r4_report(study_path; output = joinpath("results", "summaries", "r4-first-batch"))
    manifest=TOML.parsefile(study_path)
    basedir=dirname(study_path)
    ispath(output) && error("报告目录已存在；使用新的目录，保留原证据")
    mkpath(output)
    rows=NamedTuple[]
    residuals=NamedTuple[]
    actors=NamedTuple[]
    payments=NamedTuple[]
    diagnostics=NamedTuple[]
    prices=NamedTuple[]
    for entry in manifest["runs"]
        path=joinpath(basedir, entry["directory"])
        r=read_r4_run(path)
        c=r.case
        result=r.result
        val=r.validation
        name=entry["case"]
        variant=entry["variant"]
        id=result["run_id"]
        rel=replace(relpath(abspath(path), abspath(joinpath(@__DIR__, ".."))), '\\'=>'/')
        isabspath(rel) && error("报告不得记录本机绝对路径")
        push!(
            rows,
            (
                case = name,
                variant = variant,
                run_id = id,
                input_sha256 = c.sha256,
                path = rel,
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
                    run_id = id,
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
        if haskey(result, "values")
            for x in result["ledger"]["actors"]
                push!(
                    actors,
                    (
                        run_id = id,
                        actor = x["actor"],
                        resource = x["resource"],
                        dissatisfaction = x["dissatisfaction"],
                        external = x["external"],
                        prepayment_cost = x["prepayment_cost"],
                        internal_net_cash = x["internal_net_cash"],
                        utility = x["utility"],
                    ),
                )
            end
            for x in result["ledger"]["payments"]
                push!(
                    payments,
                    (
                        run_id = id,
                        t = x["t"],
                        carrier = x["carrier"],
                        payer = x["from"],
                        payee = x["to"],
                        kind = x["kind"],
                        quantity_MWh = x["quantity_MWh"],
                        price = x["price"],
                        amount = x["amount"],
                    ),
                )
            end
            alt=deepcopy(c.data["settlement"])
            alt["P_peer"]=150.0
            alt["H_peer"]=110.0
            for (policy, kwargs) in (
                ("teaching", (; p2p_enabled = result["ledger"]["p2p_enabled"])),
                (
                    "alternative",
                    (; settlement = alt, p2p_enabled = result["ledger"]["p2p_enabled"]),
                ),
                ("no_p2p", (; p2p_enabled = false)),
            )
                ledger=r4_ledger(c, result["values"]; kwargs...)
                for x in ledger["actors"]
                    push!(
                        prices,
                        (
                            run_id = id,
                            policy = policy,
                            actor = x["actor"],
                            utility = x["utility"],
                            system_cost = ledger["operating_cost"],
                            cash_balance = ledger["cash_balance"],
                        ),
                    )
                end
            end
        end
        locals=result["local_stages"]
        if length(locals)==2 && all(haskey(x, "values") for x in locals)
            for t in 1:c.data["T"]
                net=sum(
                    x["values"]["H_src"][x["actor"]][t]-x["values"]["H_D"][x["actor"]][t] for
                    x in locals
                )
                # 由全网热守恒求DSO所需出力；若为负，DSO无吸热设备，构成解析反例。
                loss=sum(PaperRebuild.r4_loss(p) for p in c.data["heat"]["pipes"])
                push!(
                    diagnostics,
                    (
                        run_id = id,
                        t = t,
                        aggregator_heat_injection_MW = net,
                        loss_MW = loss,
                        required_DSO_heat_MW = loss-net,
                        negative_generation_proof = loss-net < -3e-6,
                    ),
                )
            end
        end
        if name=="capacity_infeasible"
            upper=sum(
                a["heat_ratio"]*a["CHP_max"]+a["COP_HP"]*a["HP_max"]+a["COP_EB"]*a["EB_max"] for
                a in c.data["actors"]
            )
            write(
                joinpath(output, "capacity-proof.toml"),
                PaperRebuild.r4_text(
                    Dict(
                        "supply_upper_MW"=>upper,
                        "load_lower_MW"=>9.0,
                        "proof"=>"9 > 1.125 MW; loss nonnegative",
                    ),
                ),
            )
        end
    end
    for (file, data) in (
        ("comparison", rows),
        ("residuals", residuals),
        ("actors", actors),
        ("payments", payments),
        ("ag0-diagnostic", diagnostics),
        ("settlement-sensitivity", prices),
    )
        CSV.write(joinpath(output, file*".csv"), data)
    end
    # 同模型A2：两独立求解器的界和成本，而不是SOCP与原等式模型的目标差。
    gu=only(filter(x->x.case=="base"&&x.variant=="central_socp", rows))
    cl=only(filter(x->x.variant=="clarabel_enumeration", rows))
    diff=abs(gu.cost-cl.cost)/max(1, abs(gu.cost))
    write(
        joinpath(output, "solver-comparison.toml"),
        PaperRebuild.r4_text(
            Dict(
                "relative_cost_difference"=>diff,
                "gurobi_gap"=>gu.gap,
                "clarabel_gap"=>cl.gap,
                "pass"=>diff<=1e-4&&gu.gap<=1e-4&&cl.gap<=1e-4,
                "model"=>"same central SOCP with per-period battery mutual exclusion",
            ),
        ),
    )
    metadata=Dict(
        "batch"=>manifest["batch"],
        "origin"=>"synthetic",
        "bargaining"=>"not_performed",
        "study_sha256"=>bytes2hex(sha256(read(study_path))),
        "script_sha256"=>bytes2hex(sha256(read(@__FILE__))),
        "runs"=>[
            Dict("run_id"=>x.run_id, "input_sha256"=>x.input_sha256, "path"=>x.path) for x in rows
        ],
    )
    write(joinpath(output, "report.toml"), PaperRebuild.r4_text(metadata))
    println("R4 report: ", abspath(output), " | same-model A2 difference=", diff)
    return rows
end
if abspath(PROGRAM_FILE)==@__FILE__
    length(ARGS) in (1, 2) || error("参数：study.toml [新报告目录]")
    r4_report(
        ARGS[1];
        output = length(ARGS)==2 ? ARGS[2] : joinpath("results", "summaries", "r4-first-batch"),
    )
end
