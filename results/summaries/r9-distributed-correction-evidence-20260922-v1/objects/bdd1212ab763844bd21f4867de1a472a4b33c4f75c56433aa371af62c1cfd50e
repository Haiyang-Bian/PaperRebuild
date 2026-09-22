"""
    solve_r9_fixed_case(case, flow; mode=:VF_VT, terminal=:literal,
        physical=false, optimizer=nothing, budget_sec=600)

给定显式管道×时段kg/s流量，求解R9前向固定流量子问题；不运行PG或注入参考调度。
默认保留字面终端；roundoff_band是显式的±2^-34 K区间解释，保留全部源温坐标。
rank_checked_rhs只作敏感性诊断，不能因右端变化微小便认定控制量和费用不受影响。
共享预算含建模及独立验证，最多600秒；原成本单位仍为CNY，不通过缩小目标改变KKT门槛。
分别保存模型/原物理/终端/日能量检查与缩减模型KKT。KKT通过仍不等于流量值函数可微。
physical=true时非凸，不采集凸子问题灵敏度。返回原值及证据，不写文件。
"""
function solve_r9_fixed_case(
    c::R2Case,
    flow;
    mode = :VF_VT,
    terminal = :literal,
    physical = false,
    optimizer = nothing,
    budget_sec = 600.0,
)
    isfinite(budget_sec) && 0 <= budget_sec <= 600 || throw(ArgumentError("预算须在0至600秒"))
    terminal in (:literal, :rank_checked_rhs, :roundoff_band) ||
        throw(ArgumentError("显式流量不能参考锚定"))
    start = r3_clock()
    m = r2_flow_matrix(c, flow)
    built = Ref{Any}()
    stage = r3_solve(
        c,
        () ->
            (built[] = build_r9_reduced_model(c; mode, flow_schedule = m, physical, terminal)),
        optimizer;
        budget_sec = 0.85budget_sec,
        deadline = start+0.85budget_sec,
    )
    r = Dict{String,Any}(
        "schema"=>"r9-fixed-run-v1",
        "input_sha256"=>c.sha256,
        "mode"=>string(mode),
        "terminal_interpretation"=>string(terminal),
        "flow_sha256"=>r2_flow_hash(m),
        "flow_schedule"=>r2_extract(m),
        "currency"=>"CNY",
        "origin"=>"synthetic",
        "physical_model"=>physical,
        "stage"=>stage,
        "status"=>stage["status"],
        "budget_sec"=>budget_sec,
        "uses_projected_gradient"=>false,
        "kkt_scope"=>"fixed_flow_reduced_SOCP_only",
        "julia_version"=>string(VERSION),
    )
    if isassigned(built)
        r["terminal_certificate"] = built[].terminal_certificate
        r["constant_checks"] =
            [Dict(string(k)=>getproperty(x, k) for k in keys(x)) for x in built[].constant_checks]
    end
    if haskey(stage, "values") && !physical && r3_clock()<start+budget_sec
        # 对偶读取失败保留已有原始候选，不将属性错误改写为整个调度失败。
        r["kkt"] = try
            r3_kkt(built[].model)
        catch err
            Dict{String,Any}(
                "trusted"=>false,
                "reason"=>"kkt_collection_error",
                "error"=>sprint(showerror, err),
            )
        end
    else
        r["kkt"] = Dict{String,Any}(
            "trusted"=>false,
            "reason"=>physical ? "nonconvex_reference" : "no_solution_or_budget",
        )
    end
    checked = validate_r9_fixed_solution(c, r; check_representation = false)
    r["validation"] = Dict(
        string(k)=>getproperty(checked, k) for k in
        (:model_pass, :physical_pass, :terminal_pass, :daily_energy_pass, :representation_pass)
    )
    r["elapsed_sec"] = r3_clock()-start
    r["wall_budget_pass"] = r["elapsed_sec"] <= budget_sec+0.1
    return r
end
