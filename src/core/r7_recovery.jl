const R7_RECOVERY_CORE_FILE = @__FILE__

"""
    R7RecoveryCase(data)

第6章给定灾前边界和一个事件窗口的恢复输入。功率MW/Mvar、能量MWh、温度K、
流率kg/s、时间h；新能源场景加权，拓扑与管流跨场景共用。仅构造输入，不求解。
采用线性配电网和双水箱代理；电池域由battery_rule显式声明，原(6-12)和式容量为旧默认。
此输入本身不证明来自最优灾前调度或通过详细热网核查。
"""
struct R7RecoveryCase
    data::Dict{String,Any}
    sha256::String
end

r7_electric_domain(d) = get(d["electric"], "recovery_domain", "all_nodes_energized_v1")
r7_partial_energization(d) = r7_electric_domain(d)=="partial_energization_v1"

function r7_check_electric_domain(d)
    rule=r7_electric_domain(d)
    rule in ("all_nodes_energized_v1", "partial_energization_v1") || error("未支持的灾后带电域")
    if haskey(d["electric"], "recovery_domain")
        source=get(d["electric"], "recovery_domain_provenance", "")
        source isa AbstractString && !isempty(strip(source)) || error("灾后带电域缺少采用依据")
    elseif haskey(d["electric"], "recovery_domain_provenance")
        error("带电域来源不能脱离显式版本")
    end
    nothing
end

function r7_electric_domain_input(c, rule, provenance)
    d=deepcopy(c.data)
    d["electric"]["recovery_domain"]=String(rule)
    d["electric"]["recovery_domain_provenance"]=String(provenance)
    d
end

"""
    with_r7_electric_domain(case, rule; provenance)

复制正常或恢复输入，显式选择灾后电网域。`partial_energization_v1`用项目式R9-RE1至RE4
区分机械开关、带电节点及带电线路；允许整个闭合分量停电，停电节点电压、设备电功率和
服务电负荷均为零。拓扑和带电状态在事件时域及新能源场景之间共用；CHP继承启停和爬坡，
不得通过停电取消已开机承诺。正常调度仍为原连接树。原`all_nodes_energized_v1`及历史输入不迁移。
此域没有增加黑启动、频率动态或热泵/水泵辅助用电模型，不能作为这些能力的认证。
"""
function with_r7_electric_domain(c::R7RecoveryCase, rule::AbstractString; provenance)
    r7_recovery_assert(c)
    R7RecoveryCase(r7_electric_domain_input(c, rule, provenance))
end

# 根的成网资格仍由输入给定；CHP还须在整个事件中已开机。GT/BES的成网可用性是显式输入假设。
function r7_available_root(c, n)
    all(
        t->any(
            g->g["electric_node"]==n &&
               g["P_max_MW"]>0 &&
               (g["kind"] in ("GT", "BES") || (g["kind"]=="CHP" && g["commitment"][t]==1)),
            c.data["devices"],
        ),
        1:c.data["periods"],
    )
end

function r7_switch_admissible(c, gamma, z)
    e=c.data["electric"]
    length(z)==length(e["lines"]) && all(x->x in (0, 1), z) || error("机械开关须为线路0/1向量")
    all(i->z[i]<=1-gamma[i], eachindex(z)) &&
        sum(
            (abs(z[i]-e["lines"][i]["base_closed"]) for i in eachindex(z) if gamma[i]==0);
            init = 0,
        )<=e["switch_budget"]
end

function r7_partial_roots(c, z, energized)
    e=c.data["electric"]
    N=e["nodes"]
    length(z)==length(e["lines"]) && all(x->x in (0, 1), z) || error("机械开关须为线路0/1向量")
    length(energized)==N && all(x->x in (0, 1), energized) || error("带电模式须为节点0/1向量")
    all(
        l->z[l]==0 || energized[e["lines"][l]["from"]]==energized[e["lines"][l]["to"]],
        eachindex(z),
    ) || return nothing
    live=[z[l]*energized[e["lines"][l]["from"]] for l in eachindex(z)]
    groups=r7_connected_components(N, [(l["from"], l["to"]) for l in e["lines"]], live)
    roots=zeros(Int, N)
    for group in groups
        energized[first(group)]==0 && continue
        edges=count(l->live[l]==1 && e["lines"][l]["from"] in group, eachindex(live))
        edges==length(group)-1 || return nothing
        candidates=filter(n->e["root_eligible"][n]==1 && r7_available_root(c, n), group)
        isempty(candidates) && return nothing
        roots[first(candidates)]=1
    end
    roots
end

function r7_recovery_mode(c, mode)
    if r7_partial_energization(c.data)
        mode isa AbstractDict && Set(keys(mode))==Set(["switch", "energized"]) ||
            error("部分带电对偶模式必须同时固定机械开关和节点带电状态")
        r7_partial_roots(c, mode["switch"], mode["energized"])===nothing &&
            error("带电恢复模式不是合格森林")
        return Dict("switch"=>Int.(mode["switch"]), "energized"=>Int.(mode["energized"]))
    end
    mode isa AbstractVector || error("旧全节点带电域仅接受原拓扑向量")
    all(x->x in (0, 1), mode) || error("拓扑须为0/1")
    Int.(mode)
end

function r7_mode_from_values(c, values)
    z=round.(Int, vec(r7_unpack(values, "z")))
    r7_partial_energization(c.data) ?
    Dict("switch"=>z, "energized"=>round.(Int, vec(r7_unpack(values, "energized")))) : z
end

r7_critical_service(d) = haskey(d, "load_service")
r7_service_objective(d) =
    r7_critical_service(d) ? "critical_electric_v1" : "total_electric_and_heat_v1"
r7_loss_objective_kind(d; worst = false) =
    (worst ? "worst_" : "") * (
        r7_critical_service(d) ? "expected_critical_electric_unserved_energy_MWh" :
        "expected_unserved_energy_MWh"
    )

function r7_check_load_service(d)
    r7_critical_service(d) || return nothing
    s=d["load_service"]
    s["schema"]=="r7-critical-load-service-v1" && s["objective"]=="critical_electric_v1" ||
        error("关键负荷服务范围未声明")
    s["power_factor_rule"]=="same_node_tan_phi" &&
    s["ordinary_rule"]=="original_total_shedding_bound" &&
    s["heat_rule"]=="excluded_from_objective_report_separately" || error("未支持的负荷分类规则")
    s["provenance"] isa AbstractString && !isempty(strip(s["provenance"])) ||
        error("关键负荷来源缺失")
    shape=(d["electric"]["nodes"], d["periods"])
    critical=r7_numbers(s["critical_load_MW"], shape, "关键电负荷"; lo = 0)
    total=r7_numbers(d["electric"]["load_MW"], shape, "总电负荷"; lo = 0)
    all(critical .<= total) || error("关键电负荷不能超过原总负荷")
    nothing
end

function r7_service_input(c, critical_load_MW, provenance)
    d=deepcopy(c.data)
    load=critical_load_MW isa AbstractMatrix ?
         [collect(critical_load_MW[n, :]) for n in axes(critical_load_MW, 1)] :
         deepcopy(critical_load_MW)
    d["load_service"]=Dict{String,Any}(
        "schema"=>"r7-critical-load-service-v1",
        "objective"=>"critical_electric_v1",
        "critical_load_MW"=>load,
        "provenance"=>String(provenance),
        "power_factor_rule"=>"same_node_tan_phi",
        "ordinary_rule"=>"original_total_shedding_bound",
        "heat_rule"=>"excluded_from_objective_report_separately",
    )
    d
end

"""
    with_r7_critical_load(case, critical_load_MW; provenance)

为正常或恢复输入建立显式关键电负荷版本；数组为节点×时段、单位MW，必须介于零与原总需求之间。
保留全部普通电负荷、热负荷、容量及原削减上界，不修改父输入。项目式R9-RL1将总电失供拆为
关键和普通两部分；R9-RL2只对关键有功失供积分，普通与热失供另报。两类采用同节点功率因数，
热削减仍受原边界控制；这不是作者未公开逐节点负荷的恢复或对全部负荷的保障。
"""
function with_r7_critical_load(c::R7RecoveryCase, critical_load_MW; provenance)
    r7_recovery_assert(c)
    R7RecoveryCase(r7_service_input(c, critical_load_MW, provenance))
end

function r7_slice_load_service!(out, d, win)
    if r7_critical_service(d)
        out["load_service"]=deepcopy(d["load_service"])
        out["load_service"]["critical_load_MW"]=[
            row[win] for row in d["load_service"]["critical_load_MW"]
        ]
    end
    out
end

function r7_record_service!(record, d)
    r7_critical_service(d) && (record["service_objective"]=r7_service_objective(d))
    record
end
function r7_check_service_record(d, record)
    if r7_critical_service(d)
        get(record, "service_objective", nothing)==r7_service_objective(d) ||
            error("结果或规格的失供范围不符")
    else
        haskey(record, "service_objective") && error("旧输入不得暗加关键负荷目标")
    end
    nothing
end

function r7_battery_rule(d)
    rule=d["battery_rule"]
    rule in ("paper_sum_bound", "per_period_exclusive_v1") || error("未声明的电池运行域")
    rule
end
r7_exclusive_battery(d) = r7_battery_rule(d)=="per_period_exclusive_v1"

# 模式按设备ID映射到时段×场景；场景依赖与原充放电控制的信息结构一致。
function r7_fixed_battery_modes(d, modes)
    modes===nothing && return nothing
    r7_exclusive_battery(d) || error("原和式域不能隐式加入固定互斥模式")
    modes isa AbstractDict || error("固定电池模式须为设备ID到时段×场景矩阵")
    ids=Set(g["id"] for g in d["devices"] if g["kind"]=="BES")
    Set(keys(modes))==ids || error("固定电池模式须覆盖全部且仅BES设备")
    shape=(d["periods"], length(d["probabilities"]))
    result=Dict{String,Matrix{Float64}}()
    for id in ids
        a=modes[id]
        a isa AbstractMatrix && size(a)==shape && all(x->x in (0, 1), a) ||
            error("固定电池模式必须为时段×场景的0/1矩阵")
        result[id]=Float64.(a)
    end
    result
end

"""
    with_r7_battery_rule(case, rule)

复制正常或恢复输入并显式选择电池运行域；不修改父输入、容量、效率或初末能量边界。
`paper_sum_bound`保留原(6-12)，`per_period_exclusive_v1`在其上增加项目式R7-B1的
逐设备、时段、场景充放互斥。新输入获得自己的哈希，不能将新域结果归入旧运行。
"""
function with_r7_battery_rule(c::R7RecoveryCase, rule::AbstractString)
    r7_recovery_assert(c)
    d=deepcopy(c.data)
    d["battery_rule"]=String(rule)
    R7RecoveryCase(d)
end

"""
    r7_battery_cycle_effect(P_ch, P_dis, eta_ch, eta_dis, dt_h)

解析核算同量移除同时充放循环的影响，输入MW、无量纲效率和h，返回净注入变化MW及
每步能量变化MWh（项目推导R7-B2）。不修改调度；能量增加可能破坏容量/末端约束，
因此不能将此恒等式当作通用可行解修复。理想双效率为1时能量变化为零。
"""
function r7_battery_cycle_effect(ch, dis, eta_ch, eta_dis, dt_h)
    all(isfinite, (ch, dis, eta_ch, eta_dis, dt_h)) &&
    ch>=0 &&
    dis>=0 &&
    0<eta_ch<=1 &&
    0<eta_dis<=1 &&
    dt_h>0 || error("电池循环解析输入错误")
    delta=min(ch, dis)
    (;
        removed_cycle_MW = delta,
        charge_MW = ch-delta,
        discharge_MW = dis-delta,
        net_injection_change_MW = 0.0,
        energy_increment_MWh = dt_h*delta*(1/eta_dis-eta_ch),
    )
end

function r7_text(x)
    io = IOBuffer()
    TOML.print(io, x; sorted = true)
    String(take!(io))
end
r7_digest(x) = bytes2hex(sha256(IOBuffer(r7_text(x))))

function r7_numbers(x, shape, name; lo = -Inf, hi = Inf)
    x isa AbstractArray || error("$(name)必须显式提供数组")
    a = length(shape) == 1 ? Float64.(x) : reduce(vcat, permutedims.(Float64.(v) for v in x))
    size(a) == shape && all(y -> isfinite(y) && lo <= y <= hi, a) || error("$(name)形状或边界错误")
    a
end

function r7_connected_components(N, ends, z)
    adjacency = [Int[] for _ in 1:N]
    for (e, (i, j)) in enumerate(ends)
        z[e] == 1 || continue
        push!(adjacency[i], j)
        push!(adjacency[j], i)
    end
    groups = Vector{Int}[]
    seen = falses(N)
    for n in 1:N
        seen[n] && continue
        group, todo = Int[], [n]
        seen[n] = true
        while !isempty(todo)
            i = pop!(todo)
            push!(group, i)
            for j in adjacency[i]
                seen[j] && continue
                seen[j] = true
                push!(todo, j)
            end
        end
        push!(groups, sort(group))
    end
    groups
end

function R7RecoveryCase(input::AbstractDict)
    d = TOML.parse(r7_text(input))
    d["schema"] == "r7-recovery-case-v1" || error("恢复输入版本错误")
    get(d, "recovery_model", "r7_recovery_checked_v1") in
    ("r7_recovery_checked_v1", "r7_recovery_port_checked_v1") || error("未支持的恢复模型")
    d["origin"] in ("synthetic", "public_adapted", "thesis_verified") || error("来源缺失")
    !isempty(strip(d["name"])) && !isempty(strip(d["preplan_id"])) || error("缺案例或灾前计划身份")
    for (key, value) in (
        "power"=>"MW",
        "reactive"=>"Mvar",
        "energy"=>"MWh",
        "time"=>"h",
        "temperature"=>"K",
        "flow"=>"kg/s",
    )
        d["units"][key] == value || error("单位错误：$key")
    end
    T = d["periods"]
    T isa Integer && T > 0 || error("事件长度错误")
    isfinite(d["dt_h"]) && d["dt_h"] > 0 || error("时间步错误")
    d["event_start"] isa Integer && d["event_start"] >= 1 || error("事件起点错误")
    isfinite(d["renewable_factor"]) && 0 <= d["renewable_factor"] <= 1 ||
        error("事件新能源折减错误")
    isfinite(d["loss_limit_MWh"]) && d["loss_limit_MWh"] >= 0 || error("失供门槛错误")
    r7_battery_rule(d)
    p = Float64.(d["probabilities"])
    !isempty(p) && all(isfinite, p) && all(>(0), p) && abs(sum(p)-1) <= 1e-8 ||
        error("场景概率错误")
    W = length(p)
    e, h = d["electric"], d["heat"]
    N, J = e["nodes"], h["nodes"]
    N isa Integer && N >= 1 && J isa Integer && J >= 2 || error("节点数错误")
    e["pcc_node"] isa Integer && 1 <= e["pcc_node"] <= N || error("PCC节点错误")
    e["flow_domain"] in ("forward_only", "signed") || error("须显式选择电支路方向解释")
    r7_check_electric_domain(d)
    0 < e["v_min_pu"] <= e["v_ref_pu"] <= e["v_max_pu"] && e["S_base_MVA"] > 0 ||
        error("电压或标幺基准错误")
    all(isfinite, [e[k] for k in ("v_min_pu", "v_ref_pu", "v_max_pu", "S_base_MVA")]) || error("非有限电网边界")
    roots = r7_numbers(e["root_eligible"], (N,), "成网根节点"; lo = 0, hi = 1)
    all(isinteger, roots) || error("根资格必须为0/1")
    for line in e["lines"]
        i, j = line["from"], line["to"]
        i isa Integer && j isa Integer && 1 <= i <= N && 1 <= j <= N && i != j ||
            error("支路节点错误")
        line["base_closed"] in (0, 1) && line["vulnerable"] isa Bool || error("支路状态错误")
        for key in ("r_pu", "x_pu", "P_max_MW", "Q_max_Mvar")
            isfinite(line[key]) && line[key] >= 0 || error("支路参数错误")
        end
    end
    e["switch_budget"] isa Integer && e["switch_budget"] >= 0 || error("动作预算错误")
    e["fault_budget"] isa Integer &&
    0 <= e["fault_budget"] <= count(l->l["vulnerable"], e["lines"]) || error("故障预算错误")
    r7_numbers(e["load_MW"], (N, T), "电负荷"; lo = 0)
    r7_check_load_service(d)
    r7_numbers(e["tan_phi"], (N,), "负荷无功比"; lo = 0)
    r7_numbers(e["shed_fraction_max"], (N,), "电负荷削减上限"; lo = 0, hi = 1)
    h["available"] === true || error("首批不支持供热网络自身故障")
    r7_numbers(h["load_MW"], (J, T), "热负荷"; lo = 0)
    r7_numbers(h["shed_fraction_max"], (J,), "热负荷削减上限"; lo = 0, hi = 1)
    for key in (
        "source_flow_max",
        "load_flow_max",
        "source_delta_min",
        "source_delta_max",
        "load_delta_min",
        "load_delta_max",
    )
        r7_numbers(h[key], (J,), key; lo = 0)
    end
    all(h["source_delta_min"] .<= h["source_delta_max"]) &&
    all(h["load_delta_min"] .<= h["load_delta_max"]) || error("端口温差范围错误")
    h["c_J_kgK"] > 0 && isfinite(h["c_J_kgK"]) && h["rho_kg_m3"] > 0 && isfinite(h["rho_kg_m3"]) ||
        error("水参数错误")
    r7_numbers(h["ambient_K"], (T,), "环境温度"; lo = 0)
    all(
        isfinite(h[key]) for
        key in ("S_min_K", "S_max_K", "R_min_K", "R_max_K", "S_reference_K", "R_reference_K")
    ) || error("非有限水箱温度")
    0 < h["R_min_K"] < h["R_max_K"] < h["S_min_K"] < h["S_max_K"] || error("水箱温度范围错误")
    h["S_min_K"] <= h["S_reference_K"] <= h["S_max_K"] &&
    h["R_min_K"] <= h["R_reference_K"] <= h["R_max_K"] || error("Taylor参考温度错误")
    maximum(h["ambient_K"]) <= h["R_min_K"] || error("首批须保持水温高于环境")
    r7_numbers(h["reference_flow_kg_s"], (T,), "参考循环流"; lo = 0)
    !isempty(h["pipes"]) || error("双水箱须有显式管内容积")
    ends = Tuple{Int,Int}[]
    for pipe in h["pipes"]
        i, j = pipe["from"], pipe["to"]
        i isa Integer && j isa Integer && 1<=i<=J && 1<=j<=J && i!=j || error("热管节点错误")
        push!(ends, (i, j))
        for key in (
            "volume_S_m3",
            "volume_R_m3",
            "flow_max_kg_s",
            "flow_change_max_kg_s",
            "UA_S_W_K",
            "UA_R_W_K",
        )
            isfinite(pipe[key]) && pipe[key] >= 0 || error("热管参数错误")
        end
        pipe["volume_S_m3"] > 0 && pipe["volume_R_m3"] > 0 || error("供回水容积必须分别为正")
        r7_numbers(
            pipe["normal_flow_kg_s"],
            (T,),
            "常态管流";
            lo = -pipe["flow_max_kg_s"],
            hi = pipe["flow_max_kg_s"],
        )
        r7_numbers(pipe["initial_S_K"], (W,), "灾前供水管温"; lo = h["S_min_K"], hi = h["S_max_K"])
        r7_numbers(pipe["initial_R_K"], (W,), "灾前回水管温"; lo = h["R_min_K"], hi = h["R_max_K"])
    end
    length(r7_connected_components(J, ends, ones(Int, length(ends)))) == 1 ||
        error("两个集总水箱不能跨不连通热网使用")
    ids = [dev["id"] for dev in d["devices"]]
    all(id -> id isa AbstractString && !isempty(strip(id)), ids) &&
    length(unique(ids)) == length(ids) || error("设备身份缺失或重复")
    for dev in d["devices"]
        dev["kind"] in ("CHP", "GT", "EB", "PV", "BES") || error("设备类别错误")
        n = dev["electric_node"]
        n isa Integer && 1 <= n <= N || error("设备电节点错误")
        isfinite(dev["P_max_MW"]) && dev["P_max_MW"] >= 0 || error("设备容量错误")
        if dev["kind"] in ("CHP", "GT")
            isfinite(dev["Q_max_Mvar"]) && dev["Q_max_Mvar"] >= 0 || error("无功容量错误")
        end
        if dev["kind"] in ("CHP", "EB")
            j = dev["heat_node"]
            j isa Integer && 1<=j<=J || error("产热节点错误")
            isfinite(dev["heat_ratio"]) && dev["heat_ratio"] > 0 || error("转换系数错误")
        end
        if dev["kind"] == "CHP"
            0 <= dev["P_min_MW"] <= dev["P_max_MW"] &&
            0 <= dev["Q_min_Mvar"] <= dev["Q_max_Mvar"] || error("CHP下界错误")
            u = r7_numbers(dev["commitment"], (T,), "继承启停"; lo = 0, hi = 1)
            all(isinteger, u) && dev["previous_commitment"] in (0, 1) || error("启停不是二值")
            r7_numbers(
                dev["previous_P_MW"],
                (W,),
                "故障前CHP出力";
                lo = dev["P_min_MW"]*dev["previous_commitment"],
                hi = dev["P_max_MW"]*dev["previous_commitment"],
            )
            for key in ("ramp_MW_h", "startup_MW", "shutdown_MW")
                isfinite(dev[key]) && dev[key] >= 0 || error("爬坡参数错误")
            end
        elseif dev["kind"] == "PV"
            r7_numbers(dev["available_MW"], (T, W), "新能源可用功率"; lo = 0, hi = dev["P_max_MW"])
        elseif dev["kind"] == "BES"
            0 <= dev["E_min_MWh"] <= dev["E_max_MWh"] && isfinite(dev["E_max_MWh"]) ||
                error("电池能量界错误")
            0 < dev["eta_ch"] <= 1 && 0 < dev["eta_dis"] <= 1 || error("电池效率错误")
            r7_numbers(
                dev["initial_MWh"],
                (W,),
                "继承电池能量";
                lo = dev["E_min_MWh"],
                hi = dev["E_max_MWh"],
            )
        end
    end
    for n in 1:N
        roots[n] == 0 && continue
        any(
            g->g["electric_node"]==n && g["kind"] in ("CHP", "GT", "BES") && g["P_max_MW"]>0,
            d["devices"],
        ) || error("成网根须有显式CHP/GT/电池；成网能力仍是输入假设")
    end
    for j in 1:J
        h["source_flow_max"][j] == 0 ||
            any(g->g["kind"] in ("CHP", "EB") && g["heat_node"]==j, d["devices"]) ||
            error("热源端口无设备")
    end
    R7RecoveryCase(d, r7_digest(d))
end

"""读取显式灾前边界与事件窗口；保存规范化输入及其哈希，不将手算边界冒充正常运行最优解。"""
load_r7_recovery_case(path::AbstractString) = R7RecoveryCase(TOML.parsefile(path))

function r7_recovery_assert(c)
    r7_digest(c.data) == c.sha256 || error("恢复输入在构造后改变")
end

r7_recovery_version(c::R7RecoveryCase) = get(c.data, "recovery_model", "r7_recovery_checked_v1")

"""
    with_r7_port_temperature_bounds(case)

返回显式的r7_recovery_port_checked_v1输入副本，不改动原案例、温度界或端口参数。
新版本在双水箱模型中增加R7-C1温区必要条件，仍非详细输运或水力模型；重复调用不改变身份。
"""
function with_r7_port_temperature_bounds(c::R7RecoveryCase)
    r7_recovery_assert(c)
    d=deepcopy(c.data)
    d["recovery_model"]="r7_recovery_port_checked_v1"
    R7RecoveryCase(d)
end

"""
    r7_port_temperature_bounds(case)

R7-C1：从既有供回温区推导源、荷端口温差与原包络的交集，单位K。
返回节点向量source_min/source_max/load_min/load_max；正流时必须落入交集。
交集为空只允许该端口流量为零，不删除原包络，不代表全网温度可重构。
"""
function r7_port_temperature_bounds(c::R7RecoveryCase)
    r7_recovery_assert(c)
    h=c.data["heat"]
    lo=h["S_min_K"]-h["R_max_K"]
    hi=h["S_max_K"]-h["R_min_K"]
    (;
        source_min = max.(h["source_delta_min"], lo),
        source_max = min.(h["source_delta_max"], hi),
        load_min = max.(h["load_delta_min"], lo),
        load_max = min.(h["load_delta_max"], hi),
    )
end

"""
    r7_island_heat_bound(case, fault)

R7-C2解析证书：在本采用无损电网中，若全部热源位于无任何有功消纳端的电孤岛，
则非负发电与电平衡迫使产热为零。R7-C1正温差下，源流为零；全网质量守恒和非负荷流
进一步迫使交付为零。返回期望热失供MWh必要下界，不求解，不认证可行或达到下界。
只对显式port_checked版本适用；只要可能存在电负荷、电锅炉或可充电电池就拒绝该孤岛推断。
"""
function r7_island_heat_bound(c::R7RecoveryCase, fault)
    r7_recovery_assert(c)
    r7_check_fault(c, fault)
    d=c.data
    e=d["electric"]
    h=d["heat"]
    result=Dict{String,Any}(
        "schema"=>"r7-port-island-bound-v1",
        "case_sha256"=>c.sha256,
        "fault"=>Int.(fault),
        "version"=>r7_recovery_version(c),
        "applicable"=>false,
        "detailed_heat_validated"=>false,
        "attainability_verified"=>false,
    )
    if r7_recovery_version(c)!="r7_recovery_port_checked_v1"
        result["reason"]="temperature_compatible_ports_not_enforced"
        return result
    end
    # 健康线路全连通是任意允许恢复拓扑的超图；只有这张图也隔离时才作此推断。
    groups=r7_connected_components(
        e["nodes"],
        [(l["from"], l["to"]) for l in e["lines"]],
        1 .- Int.(fault),
    )
    no_sink=Vector{Int}[]
    for nodes in groups
        demand=any(any(>(0), e["load_MW"][n]) for n in nodes)
        consumer=any(
            g["electric_node"] in nodes && g["kind"] in ("EB", "BES") && g["P_max_MW"]>0 for
            g in d["devices"]
        )
        !demand && !consumer && push!(no_sink, nodes)
    end
    zero_nodes=isempty(no_sink) ? Int[] : vcat(no_sink...)
    result["no_sink_electric_components"]=no_sink
    sources=[g for g in d["devices"] if g["kind"] in ("CHP", "EB") && g["P_max_MW"]>0]
    if !all(g->g["electric_node"] in zero_nodes, sources)
        result["reason"]="some_heat_source_may_have_electric_consumption"
        return result
    end
    result["applicable"]=true
    result["reason"]="all_sources_zero_then_mass_balance_forces_all_load_flows_zero"
    result["minimum_heat_loss_MWh"]=d["dt_h"]*sum(sum(row) for row in h["load_MW"])*sum(
        d["probabilities"],
    )
    result["hard_shedding_conflict"]=any(
        h["shed_fraction_max"][j]<1 && any(>(0), h["load_MW"][j]) for j in 1:h["nodes"]
    )
    result
end

"""
    r7_faults(case)

按(6-50)枚举不超过故障预算的全部线路组合，包含零内部断线；事件期PCC仍断开。
首批穷举限20条脆弱线路，超出时显式拒绝，不静默截断最坏情形集合。
"""
function r7_faults(c::R7RecoveryCase)
    r7_recovery_assert(c)
    lines = c.data["electric"]["lines"]
    eligible = findall(l->l["vulnerable"], lines)
    length(eligible) <= 20 || error("故障穷举超过首批规模；使用后续对手算法")
    out = Vector{Int}[]
    for mask in 0:(2^length(eligible)-1)
        count_ones(mask) <= c.data["electric"]["fault_budget"] || continue
        gamma = zeros(Int, length(lines))
        for (k, e) in enumerate(eligible)
            gamma[e] = (mask >> (k-1)) & 1
        end
        push!(out, gamma)
    end
    out
end

function r7_check_fault(c, gamma)
    ls = c.data["electric"]["lines"]
    length(gamma)==length(ls) && all(x->x in (0, 1), gamma) || error("故障向量错误")
    sum(gamma)<=c.data["electric"]["fault_budget"] &&
    all(i->ls[i]["vulnerable"]||gamma[i]==0, eachindex(ls)) || error("故障不在允许集合")
end

function r7_heat_constants(c)
    h = c.data["heat"]
    C = Dict(
        side=>h["c_J_kgK"]*h["rho_kg_m3"]*sum(p["volume_$(side)_m3"] for p in h["pipes"])/3.6e9
        for side in ("S", "R")
    )
    E0 = Dict(
        side=>[
            h["c_J_kgK"]*h["rho_kg_m3"]/3.6e9*sum(
                p["volume_$(side)_m3"]*(p["initial_$(side)_K"][w]-h["$(side)_min_K"]) for
                p in h["pipes"]
            ) for w in eachindex(c.data["probabilities"])
        ] for side in ("S", "R")
    )
    (; C, E0)
end

r7_pack(a) = Dict("shape"=>collect(size(a)), "data"=>Float64.(vec(Array(a))))
r7_unpack(v, k) = reshape(Float64.(v[k]["data"]), Tuple(Int.(v[k]["shape"])))
