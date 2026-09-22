"""
    r7_initial_profile(state; provenance)

把显式R7PipeState保存为`r7-initial-profile-v2`正常管温输入，保留每段常量、指数幅值、
空间衰减率及方向；质量kg、温度K、衰减率1/kg。对应项目R9-RI1，禁止以平均温度替代空间分布。
provenance说明初态的构造/来源；本函数不推测历史、不求解、不写文件。
旧`mass_kg/temperature_K`分段常温输入继续保持原含义及字节身份。
"""
function r7_initial_profile(state::R7PipeState; provenance)
    r7_pipe_check(state)
    provenance isa AbstractString && !isempty(strip(provenance)) || error("空间初态缺少来源")
    Dict{String,Any}(
        "schema"=>"r7-initial-profile-v2",
        "provenance"=>String(provenance),
        "segments"=>[
            Dict{String,Any}(
                "mass_kg"=>s.mass_kg,
                "base_K"=>s.base_K,
                "amplitude_K"=>s.amplitude_K,
                "rate_per_kg"=>s.rate_per_kg,
                "from_left"=>s.from_left,
            ) for s in state.segments
        ],
    )
end

r7_has_spatial_initial(d) = any(
    haskey(profile, "schema") for p in d["heat"]["pipes"] for side in ("S", "R") for
    profile in p["initial_$(side)_profiles"]
)

function r7_initial_state(profile)
    if !haskey(profile, "schema")
        return r7_pipe_state(profile["mass_kg"], profile["temperature_K"])
    end
    profile["schema"]=="r7-initial-profile-v2" || error("未知空间初态版本")
    provenance=get(profile, "provenance", "")
    provenance isa AbstractString && !isempty(strip(provenance)) || error("空间初态缺少来源")
    !haskey(profile, "mass_kg") && !haskey(profile, "temperature_K") ||
        error("不能混用两种初态表示")
    all(s->s["from_left"] isa Bool, profile["segments"]) || error("空间方向必须为布尔值")
    state=R7PipeState([
        R7PipeSegment(
            Float64(s["mass_kg"]),
            Float64(s["base_K"]),
            Float64(s["amplitude_K"]),
            Float64(s["rate_per_kg"]),
            s["from_left"],
        ) for s in profile["segments"]
    ])
    r7_pipe_check(state)
    state
end

function r7_initial_mean(profile, cp, reference)
    # 旧版本保留原有运算顺序，不重写历史模板的浮点字节。
    !haskey(profile, "schema") &&
        return sum(profile["mass_kg"] .* profile["temperature_K"])/sum(profile["mass_kg"])
    r7_pipe_inventory(r7_initial_state(profile); cp_J_kgK = cp, reference_K = reference).mean_K
end

function r7_initial_transport(profile, mass, lo, hi)
    if !haskey(profile, "schema")
        return (;
            mass = profile["mass_kg"] ./ mass,
            mean = (profile["temperature_K"] .- lo) ./ (hi-lo),
            spatial = nothing,
        )
    end
    state=r7_initial_state(profile)
    spatial=[
        (;
            base = (s.base_K-lo)/(hi-lo),
            amplitude = s.amplitude_K/(hi-lo),
            rate = s.rate_per_kg*mass,
            from_left = s.from_left,
        ) for s in state.segments
    ]
    weights=[s.mass_kg/mass for s in state.segments]
    means=[
        s.base+s.amplitude*(s.rate==0 ? 1.0 : -expm1(-s.rate*w)/(s.rate*w)) for
        (s, w) in zip(spatial, weights)
    ]
    (; mass = weights, mean = means, spatial)
end
