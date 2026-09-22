"""
    R4ThermalSpec(; policy=:joint, electric=:exact, loss=:exponential,
        supply_K=(343.15,363.15), return_K=(303.15,323.15), flow_floor=1e-4)

R4-T1至T6采用的逐时稳态热网版本。日阀门连通与逐时循环分开；允许闲置支路。
loss=:reference沿用参考供回温散热，:exponential采用正流量下的稳态管道传热解。
温度单位K，流量kg/s，flow_floor是显式项目运行下限，并非作者参数。
不含停流冷却、重启瞬态、泵耗、水压或旁通；不能解释为完整动态热网。
"""
struct R4ThermalSpec
    policy::Symbol
    electric::Symbol
    loss::Symbol
    supply_K::Tuple{Float64,Float64}
    return_K::Tuple{Float64,Float64}
    flow_floor::Float64
    function R4ThermalSpec(;
        policy = :joint,
        electric = :exact,
        loss = :exponential,
        supply_K = (343.15, 363.15),
        return_K = (303.15, 323.15),
        flow_floor = 1e-4,
    )
        R4ReconfigurationSpec(; policy, electric)
        loss in (:reference, :exponential) || error("未知热损耗版本")
        all(x->length(x)==2 && all(isfinite, x) && 0<x[1]<x[2], (supply_K, return_K)) ||
            error("温度边界必须有限递增，单位K")
        supply_K[1]>return_K[2] || error("本版本要求供温下界高于回温上界")
        isfinite(flow_floor) && flow_floor>0 || error("运行流量下限必须有限正值")
        new(
            policy,
            electric,
            loss,
            Tuple(Float64.(supply_K)),
            Tuple(Float64.(return_K)),
            Float64(flow_floor),
        )
    end
end

function r4_thermal_spec(s::R4ThermalSpec)
    Dict(
        "version"=>"r4_thermal_checked_v1",
        "policy"=>String(s.policy),
        "electric"=>String(s.electric),
        "loss"=>String(s.loss),
        "supply_K"=>collect(s.supply_K),
        "return_K"=>collect(s.return_K),
        "flow_floor"=>s.flow_floor,
        "idle_rule"=>"decoupled_steady_no_transport",
        "bypass"=>"absent",
        "pressure_pumps_dynamics"=>false,
    )
end
function r4_thermal_spec(d::AbstractDict)
    d["version"]=="r4_thermal_checked_v1" || error("未知热网版本")
    d["idle_rule"]=="decoupled_steady_no_transport" &&
    d["bypass"]=="absent" &&
    d["pressure_pumps_dynamics"]==false || error("热网适用范围不匹配")
    R4ThermalSpec(;
        policy = Symbol(d["policy"]),
        electric = Symbol(d["electric"]),
        loss = Symbol(d["loss"]),
        supply_K = Tuple(d["supply_K"]),
        return_K = Tuple(d["return_K"]),
        flow_floor = d["flow_floor"],
    )
end

"""
    r4_steady_pipe(inlet_K, ambient_K, mass_kg_s, UA_W_K; cp=4180.0)

纯数值R4-T2稳态单管解析解。对正向正流量积分m*cp*dT/dx=-U*(T-Ta)，
返回出口温度K和损失热功率MW。UA为单位长度传热系数乘长度(W/K)，不额外乘面积。
拒绝零/负流量；停流冷却需要管内储热状态，本函数不将其当成稳态输运。
"""
function r4_steady_pipe(inlet_K, ambient_K, mass_kg_s, UA_W_K; cp = 4180.0)
    all(isfinite, (inlet_K, ambient_K, mass_kg_s, UA_W_K, cp)) || error("管道输入非有限")
    inlet_K>=ambient_K>0 && mass_kg_s>0 && UA_W_K>=0 && cp>0 ||
        error("需要正流量、正比热及不低于环境的入口温度")
    decay=exp(-UA_W_K/(cp*mass_kg_s))
    outlet=ambient_K+(inlet_K-ambient_K)*decay
    # expm1避免小损耗相减丢失精度；这也是手算/单位检查入口。
    loss=cp*mass_kg_s*(inlet_K-ambient_K)*(-expm1(-UA_W_K/(cp*mass_kg_s)))/1e6
    (; outlet_K = outlet, loss_MW = loss)
end

"""
    r4_thermal_min_flow(case, spec)

由冻结温度带推导每条运行弧的必要最小流量(kg/s)，与显式flow_floor取最大值。
指数式使用最大入口/最小出口温度；参考式使用冻结损耗/最大允许温降。
仅是必要条件，不替代节点混合与源荷温差；与管道容量冲突时由模型判不可行。
"""
function r4_thermal_min_flow(c::R4Case, s::R4ThermalSpec)
    h=c.data["heat"]
    cp=h["cp"]
    values=Float64[]
    for p in h["pipes"]
        Ta=p["ambient_K"]
        s.return_K[1]>Ta || error("当前热模型不支持温度边界穿过环境温度")
        UA=p["U_W_mK"]*p["length_m"]
        mins=Float64[s.flow_floor]
        for (band, ref) in ((s.supply_K, p["S_ref_K"]), (s.return_K, p["R_ref_K"]))
            ref>=Ta || error("参考散热不得从环境吸热")
            push!(
                mins,
                s.loss==:exponential ? UA/(cp*log((band[2]-Ta)/(band[1]-Ta))) :
                UA*(ref-Ta)/(cp*(band[2]-band[1])),
            )
        end
        push!(values, maximum(mins))
    end
    values
end

function r4_thermal_mass(c, schedule)
    schedule===nothing && return nothing
    T=c.data["T"]
    out=Dict{String,Matrix{Float64}}()
    for key in ("m_pipe", "m_source", "m_load")
        n=key=="m_pipe" ? length(c.data["heat"]["pipes"]) : 3
        haskey(schedule, key) || error("固定流量缺少$key")
        x=schedule[key]
        a=x isa AbstractMatrix ? Matrix{Float64}(x) : r4_heat_matrix(schedule, key, n, T)
        size(a)==(n, T) && all(x->isfinite(x)&&x>=0, a) || error("固定流量形状/取值错误")
        caps=key=="m_pipe" ? [p["flow_max"] for p in c.data["heat"]["pipes"]] :
             [a["port_flow_max"] for a in c.data["actors"]]
        all(a[i, t]<=caps[i] for i in 1:n, t in 1:T) || error("固定流量超容量")
        out[key]=a
    end
    pipes=c.data["heat"]["pipes"]
    for i in 1:3, t in 1:T
        net=out["m_source"][i, t]-out["m_load"][i, t]+sum(
            out["m_pipe"][p, t]*(x["to"]==i ? 1 : x["from"]==i ? -1 : 0) for
            (p, x) in enumerate(pipes)
        )
        abs(net)<=1e-10 || error("固定质量流计划不守恒")
    end
    out
end

function r4_thermal_options(c, s, electric_schedule, heat_open, heat_active, mass_schedule)
    haskey(c.data, "network_control") || error("需要显式候选图；旧输入不隐式迁移")
    mins=r4_thermal_min_flow(c, s)
    mass=r4_thermal_mass(c, mass_schedule)
    if mass!==nothing
        active=Int.(mass["m_pipe"] .> 0)
        all(
            mass["m_pipe"][p, t]==0 || mass["m_pipe"][p, t]>=mins[p] for
            p in eachindex(mins), t in 1:c.data["T"]
        ) || error("固定流量低于运行下限")
        heat_active===nothing || heat_active==active || error("固定流量与运行方向冲突")
        heat_active=active
    end
    switching=(;
        policy = s.policy,
        electric_schedule,
        heat_open,
        heat_direction = nothing,
        heat_active,
        allow_idle = true,
    )
    thermal=(; spec = s, mass_schedule = mass, min_flow = mins)
    (; switching, thermal)
end
