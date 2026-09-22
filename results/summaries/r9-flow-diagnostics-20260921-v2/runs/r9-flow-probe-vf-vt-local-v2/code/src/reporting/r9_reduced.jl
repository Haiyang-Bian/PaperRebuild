"""
    r9_daily_heat_balance(case, values)

从保存的端口热功率、管流和入口/出口温度独立核算整日热量，单位MWh。
返回产热、交付负荷、管道净热差、残差及沿用上一批的1e-6*max(1,产热)门槛。
净热差包括时域内库存变化；仅在另行通过周期状态检查后才能解释成周期热损耗。
"""
function r9_daily_heat_balance(c::R2Case, v)
    d, h = c.data, c.data["heat"]
    source =
        d["dt_h"]*sum(
            sum(v["H_port"][j]) for (j, n) in enumerate(h["nodes"]) if n["role"] == "source"
        )
    load = d["dt_h"]*sum(sum(n["H_MW"]) for n in h["nodes"])
    pipe_net =
        d["dt_h"]*h["cp_J_kgK"]/1e6*sum(
            v["m_pipe"][p][t]*(v["tau_"*side*"_in"][p][t]-v["tau_"*side*"_out"][p][t]) for
            p in eachindex(h["pipes"]), t in 1:d["T"], side in ("S", "R")
        )
    residual = abs(source-load-pipe_net)
    tolerance = 1e-6max(1, abs(source))
    return (;
        source_MWh = source,
        load_MWh = load,
        pipe_net_MWh = pipe_net,
        residual_MWh = residual,
        tolerance_MWh = tolerance,
        pass = isfinite(residual)&&residual <= tolerance,
    )
end

"""
    solve_r9_reduced_case(case; mode=:CF_CT, physical=false, optimizer=nothing, budget_sec=600)

执行固定流量前向代入版本，预算、币种、原式回代和终端检查与R9旧入口一致。
额外保存常数行证据哈希及整日能量核验；不会调用旧失败运行的优化器或覆盖其结果。
旧验证器重验完整温度、质量、设备、电网与水压关系；只在其通过后报告相应可行性。
求解器仅返回接近可行时，原始候选另存diagnostic_candidate，供独立回代；不改变正式状态或费用完成判定。
"""
function solve_r9_reduced_case(
    c::R2Case;
    mode = :CF_CT,
    physical = false,
    optimizer = nothing,
    budget_sec = 600.0,
    terminal = :literal,
)
    isfinite(budget_sec) && 0 <= budget_sec <= 600 || throw(ArgumentError("预算须在0到600秒"))
    start = r3_clock()
    built = Ref{Any}()
    stage = r3_solve(
        c,
        () -> (built[] = build_r9_reduced_model(c; mode, physical, terminal)),
        optimizer;
        budget_sec = 0.9budget_sec,
        deadline = start+0.9budget_sec,
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
        "representation"=>"r9_forward_substitution_v1",
    )
    r["terminal_interpretation"] = string(terminal)
    if isassigned(built)
        b = built[]
        r["terminal_certificate"] = b.terminal_certificate
        rows = [Dict(string(k)=>getproperty(x, k) for k in keys(x)) for x in b.constant_checks]
        r["representation_certificate"] = Dict(
            "constant_count"=>length(rows),
            "constant_checks_sha256"=>r9_hash(Dict("rows"=>rows)),
            "constant_max_ratio"=>maximum(
                x.residual/x.tolerance for x in b.constant_checks;
                init = 0.0,
            ),
            "variable_count"=>num_variables(b.model),
            "constraint_count"=>num_constraints(b.model; count_variable_in_set_constraints = true),
            "temperature_centre_K"=>b.temperature_centre_K,
        )
    end
    validation = validate_r9_reduced_solution(c, r; check_representation = false)
    r["validation"] = Dict(
        "model_pass"=>validation.model_pass,
        "physical_pass"=>validation.physical_pass,
        "terminal_pass"=>validation.terminal_pass,
    )
    if haskey(stage, "values")
        energy = r9_daily_heat_balance(c, stage["values"])
        r["daily_heat"] = Dict(string(k)=>getproperty(energy, k) for k in keys(energy))
    elseif isassigned(built) &&
           has_values(built[].model) &&
           get(stage, "primal", "") == "NEARLY_FEASIBLE_POINT"
        # 原接口拒绝近可行点的行为保持；诊断证据有独立入口，不能冒充正式调度。
        near = deepcopy(stage)
        near["values"] = Dict(k => r2_extract(v) for (k, v) in built[].variables)
        near["solver_objective"] = objective_value(built[].model)
        near["operating_cost"] = r3_operating_cost(c, near["values"])
        near["objective"] = near["operating_cost"]
        candidate = merge(r, Dict("stage" => near))
        checked = validate_r9_reduced_solution(c, candidate; check_representation = false)
        energy = r9_daily_heat_balance(c, near["values"])
        r["diagnostic_candidate"] = Dict(
            "accepted_by_solver_status" => false,
            "stage" => near,
            "validation" => Dict(
                "model_pass" => checked.model_pass,
                "physical_pass" => checked.physical_pass,
                "terminal_pass" => checked.terminal_pass,
            ),
            "daily_heat" => Dict(string(k) => getproperty(energy, k) for k in keys(energy)),
        )
    end
    r["elapsed_sec"] = r3_clock()-start
    r["wall_budget_pass"] = r["elapsed_sec"] <= budget_sec+0.1
    return r
end
