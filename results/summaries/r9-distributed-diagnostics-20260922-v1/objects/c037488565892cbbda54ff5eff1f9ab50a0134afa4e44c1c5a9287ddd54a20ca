"""
    R4HeatCompatibilitySpec(; level=:mixing, fixed_mass=false,
        supply_K=(343.15, 363.15), return_K=(303.15, 323.15))

固定设备、拓扑及管道热功率后的稳态相容性核查。温度边界为显式项目假设，
不是论文参数；envelope只检查必要条件，mixing另检查供回水节点混合。
沿用父运行的参考温度冻结损耗，不检查水压、时延或精确温变损耗。
"""
struct R4HeatCompatibilitySpec
    level::Symbol
    fixed_mass::Bool
    supply_K::Tuple{Float64,Float64}
    return_K::Tuple{Float64,Float64}
    function R4HeatCompatibilitySpec(;
        level = :mixing,
        fixed_mass = false,
        supply_K = (343.15, 363.15),
        return_K = (303.15, 323.15),
    )
        level in (:envelope, :mixing) || error("未知热相容性层级")
        all(x->length(x)==2 && all(isfinite, x) && 0<x[1]<x[2], (supply_K, return_K)) ||
            error("温度边界必须有限、递增，单位K")
        supply_K[2]>return_K[1] || error("供回温边界不能传递正热量")
        new(level, fixed_mass, Tuple(Float64.(supply_K)), Tuple(Float64.(return_K)))
    end
end

function r4_heat_spec(s::R4HeatCompatibilitySpec)
    Dict(
        "version"=>"r4_heat_compatibility_v1",
        "level"=>String(s.level),
        "fixed_mass"=>s.fixed_mass,
        "supply_K"=>collect(s.supply_K),
        "return_K"=>collect(s.return_K),
    )
end
function r4_heat_spec(d::AbstractDict)
    d["version"]=="r4_heat_compatibility_v1" || error("未知热核查版本")
    R4HeatCompatibilitySpec(;
        level = Symbol(d["level"]),
        fixed_mass = d["fixed_mass"],
        supply_K = Tuple(d["supply_K"]),
        return_K = Tuple(d["return_K"]),
    )
end

function r4_heat_matrix(v, key, n, T)
    haskey(v, key) && length(v[key])==n && all(x->length(x)==T && all(isfinite, x), v[key]) ||
        error("缺失/非法数组：$key")
    [Float64(v[key][i][t]) for i in 1:n, t in 1:T]
end

function r4_heat_data(c, parent)
    parent["input_sha256"]==c.sha256 || error("父运行输入不匹配")
    d=c.data
    T=d["T"]
    pipes=d["heat"]["pipes"]
    n=length(pipes)
    v=parent["values"]
    q=Dict(
        k=>r4_heat_matrix(v, k, k in ("H_src", "H_D", "m_source", "m_load") ? 3 : n, T) for
        k in ("H_src", "H_D", "H_in", "H_out", "m_pipe", "m_source", "m_load")
    )
    on=haskey(d, "network_control") ? r4_heat_matrix(v, "u_H_arc", n, T) : ones(n, T)
    all(x->abs(x-round(x))<=1e-6 && -1e-6<=x<=1+1e-6, on) || error("热方向不是合法离散值")
    # 先校验整数偏差，再把已经确定的拓扑作为离散参数；原始值仍在父运行中。
    on=round.(on)
    Ls=[
        1e-6*p["U_W_mK"]*p["length_m"]*(p["S_ref_K"]-p["ambient_K"])*on[i, t] for
        (i, p) in enumerate(pipes), t in 1:T
    ]
    Lr=[
        1e-6*p["U_W_mK"]*p["length_m"]*(p["R_ref_K"]-p["ambient_K"])*on[i, t] for
        (i, p) in enumerate(pipes), t in 1:T
    ]
    all(x->x>=0, Ls) && all(x->x>=0, Lr) || error("当前核查不支持从环境吸热")
    p_tol=1e-6*(1+d["electric"]["grid_max"])
    f_tol=1e-6*(1+maximum(p["flow_max"] for p in pipes))
    (; q, on, Ls, Lr, p_tol, f_tol, cp = d["heat"]["cp"]/1e6, T, pipes)
end

r4_heat_parent_hash(parent) = bytes2hex(sha256(r4_text(parent)))
