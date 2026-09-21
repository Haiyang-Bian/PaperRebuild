function r9_trading_summary(v)
    d=Dict{String,Any}(k=>deepcopy(x) for (k, x) in v if k!="rows")
    d["row_count"]=length(v["rows"])
    d["failed_row_count"]=count(x->!x["pass"], v["rows"])
    d
end

# 固定整数不是只看一个标签；逐阶段核对完整选择，防止固定方案不同却宣称同模型。
function r9_trading_mode_identity(c, stages)
    T=c.data["T"]
    sizes=Dict(
        "z_storage"=>(length(c.data["devices"]), T),
        "heat_direction"=>(length(c.data["heat"]["pipes"]), T),
    )
    if haskey(c.data, "network_control")
        sizes["u_E"]=(length(c.data["electric"]["edges"]), T)
        sizes["u_H"]=(length(c.data["heat"]["pipes"]), 1)
    end
    signatures=String[]
    for s in stages
        modes=s["fixed_modes"]
        Set(keys(modes))==Set(keys(sizes)) || error("固定模式字段不完整")
        normalized=Dict{String,Any}()
        for (key, (n, nt)) in sizes
            rows=modes[key]
            length(rows)==n && all(row->length(row)==nt, rows) || error("固定模式形状不符")
            all(x->x in (0, 1), Iterators.flatten(rows)) || error("固定模式必须为0/1")
            normalized[key]=[Int.(row) for row in rows]
        end
        push!(signatures, bytes2hex(sha256(r4_text(normalized))))
    end
    all(==(first(signatures)), signatures) || error("阶段间固定整数选择发生改变")
    first(signatures)
end

function r9_trading_stage_certificate(s, v)
    status=s["termination"]=="LICENSE_MISSING" ? "license_missing" :
           r2_status([s], 1, haskey(s, "values"), s["budget_exhausted_at_return"])
    status==s["status"] || error("原始求解状态与阶段状态不一致")
    complete=false
    if haskey(s, "values") && haskey(s, "objective_bound") && isfinite(s["solver_objective"])
        obj, b=s["solver_objective"], s["objective_bound"]
        isfinite(obj) && r2_valid_bound(b, s["solver"]) || error("伪造或无效费用界")
        den=max(1.0, abs(obj))
        gap, excess=max(0.0, obj-b)/den, max(0.0, b-obj)/den
        get(s, "relative_gap", NaN)==gap && get(s, "bound_upper_excess", NaN)==excess ||
            error("费用界口径改变")
        complete=status=="solver_optimal" && v["model_pass"] && gap<=1e-4 && excess<=1e-4
    end
    complete==s["cost_optimization_complete"] || error("费用完成状态不能覆盖失败")
    if haskey(s, "values") && haskey(s, "fixed_modes")
        # 模式只对实际启用的储能或非局部热管有效；停用变量的零值由逐式验证器检查。
        v["model_pass"] || return complete
        for (key, rows) in s["fixed_modes"]
            key in ("z_storage", "heat_direction", "u_E", "u_H") || error("未知固定整数模式")
            haskey(s["values"], key) || continue
            for i in eachindex(rows), t in eachindex(rows[i])
                if key=="z_storage" && !haskey(s, "active_storage_rows")
                    continue
                end
                key=="z_storage" && !(i in s["active_storage_rows"]) && continue
                abs(s["values"][key][i][t]-rows[i][t])<=1e-6 || error("固定模式与保存结果不符")
            end
        end
    end
    complete
end

"""
    validate_r9_trading_run(case, result)

独立复核完整交易运行的阶段链、预算记录、输入身份、冻结控制和原值判定。
原式残差由validate_r9_trading_solution逐式重算；成功状态、费用界和支付不能互相替代。
无网络阶段时只报告局部阶段失败，不把独立聚合商的局部可行当作可实施系统调度。
本验收覆盖稳态质量/能量包络；完整温度场/水压、分布式和议价始终未认证。
"""
function validate_r9_trading_run(c::R9TradingCase, r)
    r["schema"]=="r9-trading-run-v1" && r["model_version"]==r9_trading_version(c) ||
        error("运行版本错误")
    r["input_sha256"]==c.sha256 && TOML.parse(c.source_text)==c.data || error("运行输入身份改变")
    r["operation"] in ("central", "independent") && r["electric"] in ("socp", "exact") ||
        error("运行方式错误")
    r["mode_rule"] in ("free_integer", "explicit_fixed_integer_choices") || error("整数域身份错误")
    0<=r["available_budget_sec"]<=r["budget_sec"]<=600 || error("总预算口径错误")
    if haskey(r, "elapsed_sec")
        isfinite(r["elapsed_sec"]) && r["elapsed_sec"]>=0 || error("总耗时错误")
        expected_wall=!r["deadline_expired_at_start"] &&
                      r["elapsed_sec"]<=r["available_budget_sec"]+0.1
        expected_wall==r["wall_budget_pass"] || error("总预算判定错误")
    end
    r["origin"]=="synthetic" &&
    !r["uses_projected_gradient"] &&
    !r["distributed_algorithm"] &&
    !r["bargaining"] &&
    !r["full_thermal_physics_certified"] || error("研究范围被改写")
    stages=r["stages"]
    primary=r["primary_stage_index"]
    !isempty(stages) && primary in 0:length(stages) || error("阶段链缺失")
    r["mode_rule"]=="explicit_fixed_integer_choices" && r9_trading_mode_identity(c, stages)
    checks=Dict{String,Any}[]
    certs=Bool[]
    for s in stages
        s["input_sha256"]==c.sha256 &&
        s["operation"]==r["operation"] &&
        s["electric"]==r["electric"] || error("阶段身份不同")
        s["objective_kind"]==(
            s["stage"]=="local" ? "local_resource_plus_retail" : "system_resource_cost"
        ) || error("阶段目标类型被改写")
        s["allocated_budget_sec"]>=0 &&
        s["solve_elapsed_sec"]>=0 &&
        s["elapsed_sec"]>=s["solve_elapsed_sec"] || error("阶段时钟错误")
        all(isfinite, (s["allocated_budget_sec"], s["solve_elapsed_sec"], s["elapsed_sec"])) ||
            error("阶段时钟必须有限")
        s["allocated_budget_sec"]<=r["available_budget_sec"]+0.1 || error("阶段预算被重置")
        s["stage"]=="local" && s["allocated_budget_sec"]>60.1 && error("局部阶段超过60秒预算")
        (s["solve_elapsed_sec"]>=s["allocated_budget_sec"])==s["budget_exhausted_at_return"] ||
            error("时限状态被改写")
        (r["mode_rule"]=="explicit_fixed_integer_choices")==haskey(s, "fixed_modes") ||
            error("阶段整数域不同")
        v=r9_trading_checked_stage(c, s)
        push!(checks, v)
        if haskey(s, "fixed_modes")
            active=[
                i for (i, g) in enumerate(c.data["devices"]) if
                g["kind"] in ("BS", "HS") && (s["stage"]!="local" || g["owner"]==s["actor"])
            ]
            # 仅用于独立检查，不写回原运行。
            copy_s=copy(s)
            copy_s["active_storage_rows"]=active
            push!(certs, r9_trading_stage_certificate(copy_s, v))
        else
            push!(certs, r9_trading_stage_certificate(s, v))
        end
    end
    localpass=true
    if r["operation"]=="independent"
        order=sort(collect(2:length(c.data["actors"])); by = i->c.data["actors"][i]["id"])
        nlocal=primary==0 ? length(stages) : length(stages)-1
        nlocal<=length(order) || error("独立局部阶段重复")
        for i in 1:nlocal
            stages[i]["stage"]=="local" && stages[i]["actor"]==order[i] || error("独立阶段顺序错误")
            i<nlocal && !checks[i]["model_pass"] && error("失败局部之后仍有未声明后继")
        end
        localpass=nlocal==length(order) && all(checks[i]["model_pass"] for i in 1:nlocal)
        if primary>0
            localpass && primary==length(stages) && stages[primary]["stage"]=="network" ||
                error("网络阶段缺少合格独立计划")
            plans=stages[primary]["frozen_plans"]
            length(plans)==nlocal || error("冻结计划数量不符")
            for i in 1:nlocal, k in ("actor", "stage", "input_sha256", "values")
                isequal(plans[i][k], stages[i][k]) || error("网络冻结计划不是该局部原值")
            end
        else
            !localpass && r["failed_stage_status"]==last(stages)["status"] ||
                error("局部失败说明不符")
        end
    else
        length(stages)==1 && primary==1 && stages[1]["stage"]=="central" || error("集中阶段链错误")
    end
    expected_status=primary==0 ? "local_stage_failed" : stages[primary]["status"]
    r["operation"]=="independent" &&
        expected_status=="infeasible_certified" &&
        (expected_status="network_infeasible_certified")
    expected_status==r["status"] || error("总体状态与原始阶段不符")
    model=primary>0 && localpass && checks[primary]["model_pass"] && r["source_unchanged"]
    electric=primary>0 && checks[primary]["electric_original_pass"]
    heat=primary>0 && checks[primary]["heat_energy_mass_pass"]
    ledger=primary>0 && checks[primary]["ledger_pass"]
    complete=model && all(certs)
    haskey(r, "cost_optimization_complete") &&
        r["cost_optimization_complete"]!=complete &&
        error("总体费用完成状态被改写")
    Dict{String,Any}(
        "model_pass"=>model,
        "electric_original_pass"=>electric,
        "heat_energy_mass_pass"=>heat,
        "ledger_pass"=>ledger,
        "adopted_physical_pass"=>model && electric && heat && ledger,
        "full_thermal_physics_certified"=>false,
        "local_plans_pass"=>localpass,
        "local_cost_optimization_complete"=>r["operation"]=="independent" &&
                                            primary>0 &&
                                            all(certs[1:(primary-1)]),
        "cost_optimization_complete"=>complete,
        "stage_checks"=>[r9_trading_summary(v) for v in checks],
    )
end
