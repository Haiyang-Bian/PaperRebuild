"""
    solve_r4_thermal(case; optimizer, spec=R4ThermalSpec(), budget_sec=600,
        modes=nothing, electric_schedule=nothing, heat_open=nothing,
        heat_active=nothing, mass_schedule=nothing)

共享预算内求解集中稳态电热调度，保存显式运行/停流及损耗版本。温度转换为K后独立验算。
固定全离散量和流量的SOCP特例可用Clarabel；变量流量/指数式使用支持非凸关系的求解器。
许可缺失、超时、不可行和独立残差失败分别保留；不自动切换模型或注入历史参考解。
"""
function solve_r4_thermal(
    c::R4Case;
    optimizer,
    spec = R4ThermalSpec(),
    budget_sec = 600.0,
    modes = nothing,
    electric_schedule = nothing,
    heat_open = nothing,
    heat_active = nothing,
    mass_schedule = nothing,
)
    isfinite(budget_sec)&&budget_sec>0 || error("预算必须有限正数")
    start=time()
    hashes=r4_science_hashes()
    options=r4_thermal_options(c, spec, electric_schedule, heat_open, heat_active, mass_schedule)
    r=r4_solve_stage(
        c,
        R4Spec(electric = spec.electric),
        optimizer,
        start+budget_sec;
        build_options = (; options..., modes),
    )
    r["spec"]["version"]="r4_thermal_checked_v1"
    r["thermal"]=r4_thermal_spec(spec)
    r["reconfiguration"]=Dict{String,Any}("policy"=>String(spec.policy))
    for (key, x) in (
        ("electric_schedule", electric_schedule),
        ("heat_open", heat_open),
        ("heat_active", options.switching.heat_active),
    )
        x===nothing || (r["reconfiguration"][key]=x isa AbstractMatrix ? r4_rows(x) : x)
    end
    options.thermal.mass_schedule===nothing ||
        (r["mass_schedule"]=Dict(k=>r4_rows(x) for (k, x) in options.thermal.mass_schedule))
    r["source_hashes_at_solve"]=hashes
    r["budget_sec"]=Float64(budget_sec)
    if haskey(r, "values")
        for key in ("τ_S", "τ_R", "τ_source", "τ_load", "τ_S_out", "τ_R_out")
            r["values"][key]=[[273.15+100x for x in row] for row in r["values"][key]]
        end
        r["ledger"]=r4_ledger(c, r["values"])
        r["operating_cost"]=r["ledger"]["operating_cost"]
        r["switching_cost"]=r4_switch_cost(c, r["values"])
    end
    r["validation"]=validate_r4_thermal(c, r)
    r["cost_optimization_complete"] &= r["validation"]["model_pass"]
    hashes==r4_science_hashes() || error("热调度期间源码变化")
    r["elapsed_sec"]=time()-start
    r
end
