"""
    build_r9_pv_model(case; mode=:CF_CT, physical=false, optimizer=nothing)

构建第7.2节替代系统固定流量、恒/变源温调度，复用已核查WMM与径向电网。
两模式共用冻结入口历史，并约束末端足够长的入口记忆等于历史（R9-P6）。
physical=true另恢复原支路等式；原始SOCP与非凸参考显式分开。
不求解、不写文件、不包含启停成本或R3恢复尾段；VF尚未在本入口实现。
"""
function build_r9_pv_model(c::R2Case; mode = :CF_CT, physical = false, optimizer = nothing)
    mode in (:CF_CT, :CF_VT) || error("本批仅CF固定流量，禁止静默降级VF")
    audit_r9_pv_input(c).pass || error("R9输入未通过")
    operation = R3OperationSpec(c; mode, core_periods = c.data["T"], bounded_return = true)
    b = build_r3_subproblem(c, r2_flow_matrix(c); physical, optimizer, operation)
    d = c.data
    for (p, pipe) in enumerate(d["heat"]["pipes"])
        L = ceil(
            Int,
            d["heat"]["rho_kg_m3"]*pipe["area_m2"]*pipe["length_m"]/(
                3600d["dt_h"]*pipe["flow_min"]
            ),
        )
        0 < L <= min(d["T"], length(pipe["flow_history"])) || error("末端记忆长度不足")
        for t in (d["T"]-L+1):d["T"], side in ("S", "R")
            # 保存完整离散记忆，不能仅用总热库存相等冒充温度状态周期。
            r2_add!(
                b.constraints,
                "R9-P6",
                @constraint(
                    b.model,
                    b.variables["tau_"*side*"_in"][p, t] == pipe[side*"_history_K"][end+t-d["T"]]
                )
            )
        end
    end
    return merge(
        b,
        (
            variant = physical ? "r9_72_cf_original_grid_v1" : "r9_72_cf_socp_v1",
            class = r2_model_class(b.model),
        ),
    )
end
