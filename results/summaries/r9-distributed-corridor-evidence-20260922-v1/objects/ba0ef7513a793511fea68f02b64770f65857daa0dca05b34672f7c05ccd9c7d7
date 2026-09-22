# 有理数按输入Float64的确切二进制值计算；下界向下转换，避免浮点舍入产生虚假超限。
r9_cut_exact(x) = rationalize(BigInt, Float64(x); tol = 0)
function r9_cut_floor(q::Rational)
    x = Float64(q)
    isfinite(x) || error("网络割下界溢出")
    r9_cut_exact(x) > q ? prevfloat(x) : x
end

"""
    r9_electric_cut_bound(case, fault, nodes; deadline=Inf)

R9-EC1/EC2：对指定节点区域累加关键有功需求，扣除区域内最大发电及全部健康边界线路容量，
给出期望关键失供的必要下界。功率MW，时间h，结果MWh；不求解，不改变输入或原计划。
外网交换沿R7恢复模型固定为零；所有健康线按双向可用，CHP忽略启停/爬坡，电池按额定放电，
普通负荷、电锅炉耗电、热网、电压/无功与径向性均忽略。该乐观域包含现有恢复控制域。
PV使用原新能源降额和场景可用值。仅接受显式关键负荷分类，不将总电热失供冒称关键电力指标。
`nodes`必须显式给出，允许空区域；选择区域本身不是统计抽样。返回边界支路、逐时来源和有理数积分。
正下界不等于原模型的最小失供；零下界不证明可行。本接口不适用于允许灾后PCC购电的其他模型。
"""
function r9_electric_cut_bound(c::R7RecoveryCase, fault, nodes; deadline = Inf)
    (isfinite(deadline) || deadline == Inf) && time() < deadline || error("electric_cut_deadline")
    r7_recovery_assert(c)
    r7_critical_service(c.data) || error("网络割需要显式关键负荷")
    d = c.data
    e = d["electric"]
    lines = e["lines"]
    fault isa AbstractVector &&
    length(fault) == length(lines) &&
    all(x -> x isa Integer && !(x isa Bool) && x in (0, 1), fault) || error("故障须为逐线0/1整数")
    all(l -> fault[l] == 0 || lines[l]["vulnerable"], eachindex(lines)) &&
    sum(fault) <= e["fault_budget"] || error("故障不在声明域内")
    nodes isa AbstractVector && all(x -> x isa Integer && !(x isa Bool), nodes) ||
        error("区域节点须为整数")
    length(unique(nodes)) == length(nodes) && all(n -> 1 <= n <= e["nodes"], nodes) ||
        error("区域节点重复或越界")
    U = sort(Int.(nodes))
    inside = Set(U)
    boundary = [
        l for (l, x) in enumerate(lines) if
        fault[l] == 0 && ((x["from"] in inside) != (x["to"] in inside))
    ]
    zeroq = BigInt(0) // BigInt(1)
    cap = sum((r9_cut_exact(lines[l]["P_max_MW"]) for l in boundary); init = zeroq)
    sources = [g for g in d["devices"] if g["electric_node"] in inside && g["kind"] != "EB"]
    all(g -> g["kind"] in ("CHP", "GT", "PV", "BES"), sources) || error("未支持的发电上界")
    rows = Dict{String,Any}[]
    exact_energy = zeroq
    for w in eachindex(d["probabilities"]), t in 1:d["periods"]
        time() < deadline || error("electric_cut_deadline")
        demand = sum(
            (r9_cut_exact(d["load_service"]["critical_load_MW"][n][t]) for n in U);
            init = zeroq,
        )
        upper = sum(
            (
                r9_cut_exact(
                    g["kind"] == "PV" ? d["renewable_factor"] * g["available_MW"][t][w] :
                    g["P_max_MW"],
                ) for g in sources
            );
            init = zeroq,
        )
        loss = max(zeroq, demand - upper - cap)
        energy = r9_cut_exact(d["dt_h"]) * r9_cut_exact(d["probabilities"][w]) * loss
        exact_energy += energy
        push!(
            rows,
            Dict(
                "time" => t,
                "scenario" => w,
                "probability" => d["probabilities"][w],
                "critical_MW" => Float64(demand),
                "internal_generation_upper_MW" => Float64(upper),
                "boundary_import_upper_MW" => Float64(cap),
                "loss_lower_MW" => r9_cut_floor(loss),
                "weighted_energy_lower_MWh" => r9_cut_floor(energy),
                "exact_energy_numerator" => string(numerator(energy)),
                "exact_energy_denominator" => string(denominator(energy)),
            ),
        )
    end
    time() < deadline || error("electric_cut_deadline")
    # 另记严格数学门槛；对“排除现有验收”的判断沿用R7规划的门槛余量。
    margin = 1e-6 * (1 + max(1, d["loss_limit_MWh"]))
    Dict{String,Any}(
        "schema" => "r9-electric-cut-v1",
        "case_sha256" => c.sha256,
        "nodes" => U,
        "fault" => Int.(fault),
        "boundary_lines" => boundary,
        "internal_generator_ids" => [g["id"] for g in sources],
        "external_exchange" => "zero_in_R7_recovery",
        "flow_domain" => "all_healthy_lines_bidirectional",
        "generation_domain" => "CHP_capacity_without_commitment;GT_rated;PV_derated;BES_rated_without_energy",
        "dt_h" => d["dt_h"],
        "loss_limit_MWh" => d["loss_limit_MWh"],
        "rows" => rows,
        "loss_lower_MWh" => r9_cut_floor(exact_energy),
        "exact_energy_numerator" => string(numerator(exact_energy)),
        "exact_energy_denominator" => string(denominator(exact_energy)),
        "strict_threshold_excluded" => exact_energy > r9_cut_exact(d["loss_limit_MWh"]),
        "threshold_acceptance_margin_MWh" => margin,
        "threshold_excluded" => exact_energy > r9_cut_exact(d["loss_limit_MWh"] + margin),
        "original_minimum_loss_certified" => false,
        "recovery_feasibility_certified" => false,
        "optimization_performed" => false,
    )
end

"""
    validate_r9_electric_cut_bound(case, certificate; deadline=Inf)

按证书指定区域从原输入重算R9-EC1/EC2，核验身份、逐时项、精确积分和向下舍入；不读取优化约束或原调度。
不信任保存的`threshold_excluded`字段。修改任何证书值将报错；通过仅认证该必要下界及其作用域。
这是同一明确公式的保存重读检查；与调度实现的独立性由节点守恒推导、手算及独立网络LP测试共同验证。
"""
function validate_r9_electric_cut_bound(c::R7RecoveryCase, certificate; deadline = Inf)
    expected = r9_electric_cut_bound(c, certificate["fault"], certificate["nodes"]; deadline)
    isequal(expected, certificate) || error("网络割证书与原输入重算不一致")
    Dict(
        "certificate_pass" => true,
        "loss_lower_MWh" => expected["loss_lower_MWh"],
        "threshold_excluded" => expected["threshold_excluded"],
        "full_model_optimality_claimed" => false,
    )
end
