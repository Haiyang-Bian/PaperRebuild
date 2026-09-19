using SHA, TOML

"""
生成第6章选定关系的解析见证，不求解灾前/恢复调度。
单位采用MW、MWh、h、kg/s和K；对应台账R7-A1至A9及R7-C02至C04。
所有数值是用于反证和量纲检查的项目手算输入，不是论文算例参数。
"""
function ch06_audit_witnesses()
    evidence = Dict{String,Any}()
    evidence["quantifiers"] = Dict(
        "weights" => [0.5, 0.5],
        "loss_MWh" => [0.0, 2.0],
        "limit_MWh" => 1.0,
        "expected_MWh" => 1.0,
        "expected_pass" => true,
        "every_scenario_pass" => false,
    )
    # 行为新能源场景，列为共用控制；先选共用控制和逐场景选控制是不同量词。
    costs = [0 2; 2 0]
    evidence["shared_control"] = Dict(
        "costs_by_scenario" => [collect(row) for row in eachrow(costs)],
        "shared_value" => minimum(vec(sum(costs; dims = 1))) / 2,
        "scenario_adaptive_value" => sum(minimum(row) for row in eachrow(costs)) / 2,
    )
    # 两类边界均枚举，不把字面不一致通过静默改符号消除。
    evidence["switch_factor"] =
        [Dict("z" => z, "literal_allowance" => 0.1z, "adopted_allowance" => 0.1(1-z)) for z in 0:1]
    evidence["failure_window"] = Dict(
        "onset_sum" => 1,
        "literal_allowed_gamma" => [g for g in 0:1 if 1 <= 1-g],
        "text_fault_gamma" => 1,
    )
    actions = Dict{String,Any}[]
    for base in 0:1, fault in 0:1
        triples = [
            [z, on, off] for z in 0:1 for on in 0:1 for off in 0:1 if
            z == base-fault+on-off && fault+on+off <= 1 && base+on <= 1 && off <= 0
        ]
        push!(actions, Dict("base" => base, "fault" => fault, "literal_actions" => triples))
    end
    evidence["switch_actions"] = actions
    evidence["fault_sets"] = Dict(
        "line_count" => 4,
        "K" => 2,
        "masks" => [m for m in 0:15 if count_ones(m) <= 2],
        "includes_zero" => true,
    )
    # 对三节点完全图全部子图做并查集，独立检查森林恒等式。
    edges = [(1, 2), (1, 3), (2, 3)]
    forests = Dict{String,Any}[]
    for mask in 0:7
        parent = collect(1:3)
        root(v) = parent[v] == v ? v : root(parent[v])
        cycle = false
        selected = [i for i in eachindex(edges) if (mask >> (i-1)) & 1 == 1]
        for i in selected
            a, b = root.(edges[i])
            if a == b
                cycle = true
            else
                parent[b] = a
            end
        end
        cycle && continue
        components = length(unique(root.(1:3)))
        push!(
            forests,
            Dict(
                "mask" => mask,
                "nodes" => 3,
                "edges" => length(selected),
                "counted_roots" => components,
                "adopted_edge_count" => 3-components,
                "literal_edge_count" => 3-1-components,
            ),
        )
    end
    evidence["forests"] = forests
    cw, density, volume = 4200.0, 1000.0, 10.0
    capacity = cw*density*volume/3.6e9
    lower, upper, initial = 333.15, 353.15, 343.15
    energy = capacity*(initial-lower)
    evidence["energy_datum"] = Dict(
        "cw_J_per_kg_K" => cw,
        "density_kg_per_m3" => density,
        "volume_m3" => volume,
        "capacity_MWh_per_K" => capacity,
        "lower_K" => lower,
        "upper_K" => upper,
        "initial_K" => initial,
        "relative_energy_MWh" => energy,
        "maximum_energy_MWh" => capacity*(upper-lower),
        "literal_absolute_initial_MWh" => capacity*initial,
        "literal_temperature_from_relative_K" => energy/capacity,
        "reconstructed_K" => lower+energy/capacity,
    )
    source, demand, supply_loss, return_loss, exchange = 0.4, 0.3, 0.01, 0.02, 0.35
    integration = Dict{String,Any}[]
    for dt in [1.0, 0.5, 0.25]
        steps = round(Int, 1/dt)
        supply = sum(dt*(source-supply_loss-exchange) for _ in 1:steps)
        ret = sum(dt*(-demand-return_loss+exchange) for _ in 1:steps)
        push!(
            integration,
            Dict(
                "dt_h" => dt,
                "steps" => steps,
                "supply_delta_MWh" => supply,
                "return_delta_MWh" => ret,
                "total_delta_MWh" => supply+ret,
                "direct_balance_MWh" => source-demand-supply_loss-return_loss,
            ),
        )
    end
    evidence["integration"] = integration
    rem = Dict{String,Any}[]
    for flow in [9.0, 10.0, 11.0], delta in [38.0, 40.0, 42.0]
        exact = cw*flow*delta/1e6
        linear = cw*(flow*40+10*(delta-40))/1e6
        push!(
            rem,
            Dict(
                "flow_kg_per_s" => flow,
                "delta_K" => delta,
                "exact_MW" => exact,
                "linear_MW" => linear,
                "difference_MW" => exact-linear,
                "remainder_MW" => cw*(flow-10)*(delta-40)/1e6,
            ),
        )
    end
    evidence["circulation_remainder"] = rem
    # min r, -r <= -2, r自由。原值r=2，MOI方向乘子lambda=-1。
    evidence["dual"] = Dict(
        "K" => -1,
        "b" => -2,
        "f" => 1,
        "primal" => 2,
        "lambda" => -1,
        "dual_value" => 2,
        "literal_nonnegative_multiplier_feasible" => false,
    )
    # 行为故障，列为恢复模式，全部值是已精确求得的最小化值。
    table = [3 8; 10 4; 6 2]
    q = [minimum(row) for row in eachrow(table)]
    evidence["inner_bounds"] = Dict(
        "values_by_fault" => [collect(row) for row in eachrow(table)],
        "exact_fault_values" => q,
        "exact_worst" => maximum(q),
        "first_fault_value" => q[1],
        "restricted_mode_upper" => maximum(table[:, 1]),
        "valid_lower" => q[1],
        "valid_upper" => maximum(table[:, 1]),
        "literal_stop" => q[1] <= maximum(table[:, 1]),
        "correct_stop" => maximum(table[:, 1]) <= q[1],
    )
    evidence["inexact_recovery"] = Dict(
        "limit" => 4.0,
        "feasible_recovery" => 5.0,
        "lower_bound" => 2.0,
        "violation_proved" => false,
        "safety_proved" => false,
    )
    evidence["revision"] = Dict(
        "limit" => 0.4,
        "old_x" => 0.0,
        "new_x" => 0.6,
        "old_event_A_pass" => true,
        "new_event_B_pass" => true,
        "stale_flags_claim_safe" => true,
        "new_event_A_pass" => false,
        "same_revision_safe" => false,
    )
    evidence
end

ch06_audit_hash(path) = bytes2hex(sha256(read(path)))
function ch06_audit_text(x)
    io = IOBuffer()
    TOML.print(io, x; sorted = true)
    String(take!(io))
end

"""保存解析见证的新文件；已有文件拒绝覆盖。记录源文件身份，不把解析例标为论文实验。"""
function save_ch06_audit(path)
    ispath(path) && error("不覆盖已有第6章审计")
    root = normpath(joinpath(@__DIR__, ".."))
    ledger = joinpath(root, "docs/reading/ch06/audit.toml")
    data = Dict(
        "schema" => "r7-analytic-witness-v1",
        "origin" => "synthetic_analytic",
        "dispatch_implemented" => false,
        "script_sha256" => ch06_audit_hash(@__FILE__),
        "ledger_sha256" => ch06_audit_hash(ledger),
        "source_sha256" => TOML.parsefile(ledger)["source_sha256"],
        "witnesses" => ch06_audit_witnesses(),
    )
    mkpath(dirname(path))
    open(path, "w") do io
        write(io, ch06_audit_text(data))
    end
    check_ch06_audit(path)
end

"""从当前解析规则重算冻结见证；核对声明、来源与全部数值，不启动优化器。"""
function check_ch06_audit(path)
    root = normpath(joinpath(@__DIR__, ".."))
    ledger = joinpath(root, "docs/reading/ch06/audit.toml")
    d = TOML.parsefile(path)
    d["schema"] == "r7-analytic-witness-v1" &&
    d["origin"] == "synthetic_analytic" &&
    d["dispatch_implemented"] === false || error("第6章证据范围错误")
    d["script_sha256"] == ch06_audit_hash(@__FILE__) || error("解析源码变化")
    d["ledger_sha256"] == ch06_audit_hash(ledger) || error("台账变化")
    d["source_sha256"] == TOML.parsefile(ledger)["source_sha256"] || error("原件身份变化")
    isequal(d["witnesses"], ch06_audit_witnesses()) || error("解析见证与重新计算不一致")
    println("R7 selected analytic witnesses checked; no dispatch or thesis-scale claim.")
    nothing
end

if abspath(PROGRAM_FILE) == @__FILE__
    length(ARGS) == 2 || error("usage: audit_ch06.jl create|check <audit.toml>")
    if ARGS[1] == "create"
        save_ch06_audit(ARGS[2])
    elseif ARGS[1] == "check"
        check_ch06_audit(ARGS[2])
    else
        error("未知审计操作")
    end
end
