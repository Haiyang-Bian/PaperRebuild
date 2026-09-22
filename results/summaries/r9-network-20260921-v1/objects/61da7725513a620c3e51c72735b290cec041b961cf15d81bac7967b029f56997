"""
    validate_r9_fixed_solution(case, result; check_representation=true)

重读R9显式固定流量子问题；独立核对输入/流量哈希、全部物理式、周期温度/流量和日热量。
rank_checked_rhs默认从原输入重建全部终端系数与完整秩证书，并验证源温重构和坐标边界。
KKT标志不代替原值回代；受界舍入解释和字面模型保持不同身份，不重新优化。
"""
function validate_r9_fixed_solution(c::R2Case, r; check_representation = true)
    r["schema"]=="r9-fixed-run-v1" && r["input_sha256"]==c.sha256 ||
        throw(ArgumentError("固定子问题身份不符"))
    method=Symbol(r["terminal_interpretation"])
    method in (:literal, :rank_checked_rhs, :roundoff_band) || throw(ArgumentError("未知终端解释"))
    mode=Symbol(r["mode"])
    mode in (:CF_CT, :CF_VT, :VF_CT, :VF_VT) || throw(ArgumentError("未知模式"))
    flow=r2_flow_matrix(c, r["flow_schedule"])
    r2_flow_hash(flow)==r["flow_sha256"] || throw(ArgumentError("流量哈希改变"))
    stage=r["stage"]
    haskey(stage, "flow_sha256") &&
        stage["flow_sha256"]!=r["flow_sha256"] &&
        throw(ArgumentError("阶段流量改变"))
    base=validate_r3_solution(c, stage)
    haskey(stage, "values") || return (;
        model_pass = false,
        physical_pass = false,
        terminal_pass = false,
        daily_energy_pass = false,
        representation_pass = false,
        rows = base.rows,
    )
    stage["operation"]["mode"]==r["mode"] || throw(ArgumentError("阶段模式改变"))
    stage["fixed_flows"] || throw(ArgumentError("固定子问题标记改变"))
    terminal=r9_flow_terminal_rows(c, stage)
    rows=vcat(base.rows, terminal)
    record(id, entity, residual, unit, tolerance) = push!(
        rows,
        (;
            equation = id,
            scope = "model",
            entity = string(entity),
            t = 0,
            residual = Float64(abs(residual)),
            unit,
            tolerance,
            pass = isfinite(residual)&&abs(residual)<=tolerance,
        ),
    )
    cert=r["terminal_certificate"]
    cert["method"]==string(method) || throw(ArgumentError("终端证书解释改变"))
    if method==:rank_checked_rhs
        cert["interpretation_error_limit_K"]==1e-10 && !cert["reference_witness_used"] ||
            throw(ArgumentError("终端修正界或来源改变"))
        if check_representation
            rebuilt=build_r9_reduced_model(c; mode, flow_schedule = flow, terminal = method)
            rebuilt.terminal_certificate==cert || throw(ArgumentError("终端完整秩证书与输入不符"))
        end
        coordinates=cert["source_coordinates"]
        nc=length(coordinates)
        nf=cert["free_source_count"]
        nc==nf+cert["rank_exact_binary"] || throw(ArgumentError("终端自由方向遗漏"))
        U=nc==0 ? zeros(0, nf) : permutedims(hcat(cert["basis"]...))
        size(U)==(nc, nf) || throw(ArgumentError("核空间维度改变"))
        p=cert["offset_K"]
        y=stage["values"]["r9_terminal_coordinates"]
        length(p)==nc && length(y)==nf && all(isfinite, p) && all(isfinite, y) ||
            throw(ArgumentError("终端坐标非法"))
        centre=(c.data["heat"]["R_bounds_K"][1]+c.data["heat"]["S_bounds_K"][2])/2
        for (i, (j, t)) in enumerate(coordinates)
            predicted=centre+p[i]+sum(U[i, k]*y[k] for k in 1:nf; init = 0.0)
            record(
                "R9-F2-coordinate",
                "$j:$t",
                stage["values"]["tau_S_port"][j][t]-predicted,
                "K",
                1e-10,
            )
        end
        record(
            "R9-F2-error-bound",
            "all_rows",
            maximum(cert["row_error_bound_K"]; init = 0.0),
            "K",
            1e-10,
        )
        record(
            "R9-F2-coordinate-bound",
            "free",
            max(0, maximum(abs, y; init = 0.0)-cert["source_coordinate_bound_K"]),
            "K",
            1e-10,
        )
    elseif method==:roundoff_band
        cert["radius_K"]==2.0^-34 &&
        cert["interpretation_error_limit_K"]==1e-10 &&
        !cert["reference_witness_used"] || throw(ArgumentError("舍入区间约定改变"))
        if check_representation
            rebuilt=build_r9_reduced_model(c; mode, flow_schedule = flow, terminal = method)
            rebuilt.terminal_certificate==cert || throw(ArgumentError("终端区间与输入不符"))
        end
        # 不读取求解器的终端行值，直接核对保存的物理入口温度。
        # 1e-10是本数值解释的独立输出门槛，既有A1的1e-4 K保持原样。
        for row in terminal
            row.unit=="K" || continue
            record("R9-F3-adopted-terminal", row.entity, row.residual, "K", 1e-10)
        end
    end
    expected_checks=check_representation ?
                    build_r9_reduced_model(c; mode, flow_schedule = flow).constant_checks : nothing
    if !isnothing(expected_checks)
        [Dict(string(k)=>getproperty(x, k) for k in keys(x)) for x in expected_checks] == r["constant_checks"] ||
            throw(ArgumentError("常数检查与输入不同"))
    end
    for (i, row) in enumerate(r["constant_checks"])
        record("R9-F1-constant", i, row["residual"], row["unit"], row["tolerance"])
    end
    representation=all(x.pass for x in rows if startswith(x.equation, "R9-F"))
    energy=r9_daily_heat_balance(c, stage["values"])
    record("R9-A1-day-energy", "network", energy.residual_MWh, "MWh", energy.tolerance_MWh)
    termpass=!isempty(terminal)&&all(x.pass for x in terminal)
    return (;
        model_pass = base.model_pass&&termpass&&representation,
        physical_pass = base.physical_pass&&termpass&&representation&&energy.pass,
        terminal_pass = termpass,
        daily_energy_pass = energy.pass,
        representation_pass = representation,
        rows,
    )
end
