using PaperRebuild, CSV, TOML, SHA

# 这里接收已经逐日回代的值。训练目标、验证选择和测试均费各自一列，不互相替代。
function r6_study_training_row(c, r)
    ready=r!==nothing
    getr(k, default) = ready ? get(r, k, default) : default
    (;
        candidate = c["id"],
        method = c["method"],
        radius = c["radius"],
        record_available = ready,
        status = getr("status", "not_recorded"),
        candidate_accepted = getr("candidate_accepted", false),
        cost_complete = getr("cost_optimization_complete", false),
        training_objective_USD = getr("training_objective_USD", NaN),
        elapsed_sec = getr("elapsed_sec", NaN),
        run_id = getr("run_id", ""),
        case_sha256 = getr("case_sha256", ""),
        result_sha256 = getr("result_sha256", ""),
    )
end

function r6_study_summary_row(split, c, summary, selected)
    s=summary===nothing ? Dict{String,Any}() : summary
    risk=get(s, "risk", Dict{String,Any}())
    q=get(s, "observed_cost_quantiles_USD", Dict{String,Any}())
    chosen=findfirst(x->x["candidate_id"]==c["id"], selected)
    (;
        split,
        candidate = c["id"],
        method = c["method"],
        radius = c["radius"],
        record_available = summary!==nothing,
        selected_for_test = chosen!==nothing,
        selected_validation_eligible = chosen===nothing ? false : selected[chosen]["validated"],
        n = get(s, "n", 0),
        passed = get(risk, "passed", 0),
        violations = get(risk, "violations", 0),
        unknown = get(risk, "unknown", 0),
        risk_status = get(risk, "status", "not_recorded"),
        lower = get(risk, "lower", NaN),
        upper = get(risk, "upper", NaN),
        epsilon = get(risk, "epsilon", NaN),
        confidence = get(risk, "one_sided_confidence", NaN),
        model_pass_days = get(s, "model_pass_days", 0),
        complete_cost_days = get(s, "complete_cost_days", 0),
        missing_cost_days = get(s, "missing_cost_days", 0),
        all_costs_complete = get(s, "all_costs_complete", false),
        mean_net_cost_USD = get(s, "mean_net_cost_USD", NaN),
        observed_mean_USD = get(s, "observed_mean_net_cost_USD", NaN),
        observed_q05_USD = get(q, "q05", NaN),
        observed_q50_USD = get(q, "q50", NaN),
        observed_q95_USD = get(q, "q95", NaN),
        model_max_excess_K = get(s, "model_max_excess_K", NaN),
        called_energy_MWh = get(s, "model_days_called_MWh", NaN),
        mismatch_MWh = get(s, "model_days_mismatch_MWh", NaN),
        call_relative_mismatch = get(s, "model_days_relative_mismatch", NaN),
    )
end

function r6_study_day_row(split, c, id, v, r = nothing)
    getv(k, default) = get(v, k, default)
    # 无训练策略时仍逐日保留未知；缺失候选的零值绝不能进入费用或交付统计。
    (;
        split,
        candidate = c["id"],
        method = c["method"],
        day_id = id,
        run_id = r===nothing ? "" : get(r, "run_id", ""),
        status = r===nothing ? "no_accepted_training_policy" : get(r, "status", "unknown"),
        model_pass = v["model_pass"],
        cost_complete = v["cost_complete"],
        comfort_outcome = v["comfort_outcome"],
        trained_label = getv("trained_label", -1),
        net_cost_USD = getv("operating_net_cost", NaN),
        day_ahead_USD = getv("day_ahead_cost", NaN),
        device_USD = getv("device_cost", NaN),
        real_time_USD = getv("real_time_settlement", NaN),
        delivery_penalty_USD = getv("delivery_penalty", NaN),
        peak_excess_K = getv("peak_excess_K", NaN),
        called_energy_MWh = getv("called_energy_MWh", NaN),
        mismatch_MWh = getv("mismatch_MWh", NaN),
        capacity_budget_MWh = getv("mismatch_limit_MWh", NaN),
        call_relative_mismatch = getv("call_relative_mismatch", NaN),
    )
end

function r6_study_pair_table(rows, methods, statistics)
    table=NamedTuple[]
    for i in 1:length(methods), j in (i+1):length(methods)
        a=filter(r->r.split=="test"&&r.method==methods[i], rows)
        b=filter(r->r.split=="test"&&r.method==methods[j], rows)
        (isempty(a)||isempty(b)) && continue
        # 缺失费用不能删去；r6_paired_costs只在全部同日配对完成后生成总体差及区间。
        cost(r) = r.cost_complete ? r.net_cost_USD : missing
        x=r6_paired_costs(
            [r.day_id for r in a],
            cost.(a),
            [r.day_id for r in b],
            cost.(b);
            seed = statistics["bootstrap_seed"],
            replicates = statistics["bootstrap_replicates"],
            confidence = statistics["confidence"],
        )
        push!(
            table,
            (;
                method_a = methods[i],
                method_b = methods[j],
                direction = x["direction"],
                n = x["n"],
                missing_pairs = x["missing_pairs"],
                status = x["status"],
                mean_difference_USD = get(x, "mean_difference", NaN),
                lower_USD = get(x, "lower", NaN),
                upper_USD = get(x, "upper", NaN),
                seed = x["seed"],
                replicates = x["replicates"],
                confidence = x["confidence"],
            ),
        )
    end
    table
end

function r6_study_table_bytes(tables)
    files=Dict{String,Vector{UInt8}}()
    for (name, rows) in tables
        isempty(rows) && continue
        for (part, firstrow) in enumerate(1:5000:length(rows))
            file=length(rows)<=5000 ? name*".csv" : name*"-"*lpad(part, 3, '0')*".csv"
            io=IOBuffer()
            CSV.write(io, rows[firstrow:min(firstrow+4999, length(rows))])
            bytes=take!(io)
            length(bytes)<=5*1024^2 || error("报告分块超过单文件限制")
            files[file]=bytes
        end
    end
    files
end
