"""
    solve_r9_pv_case(case; mode=:CF_CT, physical=false, optimizer=nothing, budget_sec=600)

共享墙钟预算内执行R9固定模式调度，预留10%用于独立验证；金额CNY。
原始解不覆盖，模型A1通过后才另存κ等价重构。超时、无许可、无解与原物理失败分别保存。
本入口不改变输入、重启预算、调用直接修正或把SOCP费用界解释为VF问题的界。
"""
function solve_r9_pv_case(
    c::R2Case;
    mode = :CF_CT,
    physical = false,
    optimizer = nothing,
    budget_sec = 600.0,
)
    isfinite(budget_sec) && 0 <= budget_sec <= 600 || error("R9预算须在0到600秒")
    start = r3_clock()
    deadline = start+0.9budget_sec
    stage = r3_solve(
        c,
        ()->build_r9_pv_model(c; mode, physical),
        optimizer;
        budget_sec = 0.9budget_sec,
        deadline,
    )
    r = Dict{String,Any}(
        "schema"=>"r9-pv-run-v1",
        "input_sha256"=>c.sha256,
        "mode"=>string(mode),
        "physical_model"=>physical,
        "budget_sec"=>budget_sec,
        "currency"=>"CNY",
        "origin"=>"synthetic",
        "stage"=>stage,
        "status"=>stage["status"],
        "initial_history_fixed"=>true,
        "terminal_rule"=>c.data["r9"]["protocol"]["terminal_rule"],
        "julia_version"=>string(VERSION),
    )
    if haskey(stage, "values") && validate_r3_solution(c, stage).model_pass
        r["reconstructed"] = reconstruct_r3_pressure(c, stage)
    end
    checked = validate_r9_pv_solution(c, r)
    r["validation"] = Dict(
        "model_pass"=>checked.model_pass,
        "physical_pass"=>checked.physical_pass,
        "terminal_pass"=>checked.terminal_pass,
    )
    r["elapsed_sec"] = r3_clock()-start
    r["wall_budget_pass"] = r["elapsed_sec"] <= budget_sec+0.1
    return r
end
