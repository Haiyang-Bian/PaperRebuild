"""
    R3OperationSpec(case; mode=:VF_VT, core_periods=case.data["T"], bounded_return=true)

四模式控制约定。CF固定各管恒定参考流量；CT只固定热源端口供水温度。
参考值来自输入fixed_flow首值和S_reference_K，拒绝非恒定参考计划。
核心时段后默认固定参考流量、源温度和负荷回水温度。
tail_return_rule=:bounded仅解除尾段回温等式，仍需独立检查末端是否恢复。
bounded_return只改变显式传入此约定的新运行；旧R2/R3调用仍固定负荷回水温度。
单位：kg/s、K；core_periods与恢复尾段长度是时间步数。
"""
struct R3OperationSpec
    mode::Symbol
    core_periods::Int
    reference_flow::Vector{Float64}
    source_temperature_K::Float64
    bounded_return::Bool
    tail_return_rule::Symbol
end

# 保留旧五参数构造及默认序列化，以便历史运行哈希仍可核验。
R3OperationSpec(mode, core, flow, temperature, bounded) =
    R3OperationSpec(mode, core, flow, temperature, bounded, :fixed_reference)

function R3OperationSpec(
    c::R2Case;
    mode = :VF_VT,
    core_periods = get(get(c.data, "r3_mechanism", Dict()), "core_periods", c.data["T"]),
    bounded_return = true,
    tail_return_rule = :fixed_reference,
)
    mode in (:CF_CT, :CF_VT, :VF_CT, :VF_VT) || throw(ArgumentError("未知四模式"))
    1<=core_periods<=c.data["T"] || throw(ArgumentError("核心时段非法"))
    tail_return_rule in (:fixed_reference, :bounded) || throw(ArgumentError("未知尾段回温规则"))
    tail_return_rule==:bounded &&
        !bounded_return &&
        throw(ArgumentError("有界尾段回温须启用有界负荷回温"))
    pipes=c.data["heat"]["pipes"]
    all(maximum(abs.(p["fixed_flow"] .- first(p["fixed_flow"])))<=1e-12 for p in pipes) ||
        throw(ArgumentError("四模式参考流量必须恒定"))
    return R3OperationSpec(
        mode,
        core_periods,
        [first(p["fixed_flow"]) for p in pipes],
        c.data["heat"]["S_reference_K"],
        bounded_return,
        tail_return_rule,
    )
end

function r3_operation_dict(o::R3OperationSpec)
    d = Dict{String,Any}(
        "mode"=>string(o.mode),
        "core_periods"=>o.core_periods,
        "reference_flow"=>o.reference_flow,
        "source_temperature_K"=>o.source_temperature_K,
        "bounded_return"=>o.bounded_return,
    )
    o.tail_return_rule==:fixed_reference || (d["tail_return_rule"]=string(o.tail_return_rule))
    return d
end
function r3_operation_from_dict(d)
    return R3OperationSpec(
        Symbol(d["mode"]),
        Int(d["core_periods"]),
        Float64.(d["reference_flow"]),
        Float64(d["source_temperature_K"]),
        Bool(d["bounded_return"]),
        Symbol(get(d, "tail_return_rule", "fixed_reference")),
    )
end
function r3_operation_hash(d)
    io=IOBuffer()
    TOML.print(io, d; sorted = true)
    return bytes2hex(sha256(take!(io)))
end
r3_is_cf(o) = !isnothing(o) && o.mode in (:CF_CT, :CF_VT)
r3_is_ct(o) = !isnothing(o) && o.mode in (:CF_CT, :VF_CT)

function r3_apply_operation!(c, model, v, cs, o)
    isnothing(o) && return
    # 重新构造并比较，拒绝与输入不符的伪造参考值或非法模式。
    expected=R3OperationSpec(
        c;
        mode = o.mode,
        core_periods = o.core_periods,
        bounded_return = o.bounded_return,
        tail_return_rule = o.tail_return_rule,
    )
    r3_operation_dict(o)==r3_operation_dict(expected) ||
        throw(ArgumentError("运行模式参考值与输入不符"))
    rows=get!(cs, "R3-operation", Any[])
    for t in 1:c.data["T"]
        tail=t>o.core_periods
        if r3_is_cf(o) || tail
            for p in eachindex(o.reference_flow)
                push!(rows, @constraint(model, v["m_pipe"][p, t]==o.reference_flow[p]))
            end
        end
        for (j, n) in enumerate(c.data["heat"]["nodes"])
            if n["role"]=="source" && (r3_is_ct(o) || tail)
                push!(rows, @constraint(model, v["tau_S_port"][j, t]==o.source_temperature_K))
            elseif n["role"]=="load" && tail && o.tail_return_rule==:fixed_reference
                push!(rows, @constraint(model, v["tau_R_port"][j, t]==n["return_K"]))
            end
        end
    end
end

function r3_operation_rows!(record, c, result)
    haskey(result, "operation") || return
    op=result["operation"]
    r3_operation_hash(op)==result["operation_sha256"] || throw(ArgumentError("运行模式哈希不一致"))
    o=r3_operation_from_dict(op)
    expected=R3OperationSpec(
        c;
        mode = o.mode,
        core_periods = o.core_periods,
        bounded_return = o.bounded_return,
        tail_return_rule = o.tail_return_rule,
    )
    r3_operation_dict(expected)==op || throw(ArgumentError("运行模式参考值非法"))
    v=result["values"]
    for t in 1:c.data["T"]
        tail=t>o.core_periods
        for p in eachindex(o.reference_flow)
            (r3_is_cf(o)||tail) && record(
                "R3-operation-flow",
                "model",
                p,
                t,
                v["m_pipe"][p][t]-o.reference_flow[p],
                "kg/s",
                1e-6+1e-6*c.data["heat"]["pipes"][p]["flow_max"],
            )
        end
        for (j, n) in enumerate(c.data["heat"]["nodes"])
            if n["role"]=="source" && (r3_is_ct(o)||tail)
                record(
                    "R3-operation-source",
                    "model",
                    j,
                    t,
                    v["tau_S_port"][j][t]-o.source_temperature_K,
                    "K",
                    1e-4,
                )
            elseif n["role"]=="load" && tail && o.tail_return_rule==:fixed_reference
                record(
                    "R3-operation-return",
                    "model",
                    j,
                    t,
                    v["tau_R_port"][j][t]-n["return_K"],
                    "K",
                    1e-4,
                )
            end
        end
    end
end

# 仅截取明确声明的时间序列；历史输入及静态参数保持原字节含义。
function r3_core_data(c, periods)
    d=deepcopy(c.data)
    for key in ("grid_price", "ambient_K")
        d[key]=d[key][1:periods]
    end
    for n in d["electric"]["nodes"], key in ("P_MW", "Q_Mvar")
        n[key]=n[key][1:periods]
    end
    for n in d["heat"]["nodes"]
        n["H_MW"]=n["H_MW"][1:periods]
    end
    for p in d["heat"]["pipes"]
        p["fixed_flow"]=p["fixed_flow"][1:periods]
    end
    for g in d["devices"]
        g["availability"]=g["availability"][1:periods]
    end
    d["T"]=periods
    return d
end

"""
    r3_boundary_case(case, boundary)

从已冻结四模式输入派生边界对照。legacy_tail和bounded_return_tail保留同一案例，
后者须另传tail_return_rule=:bounded的运行约定；core_only只截取核心时段。
历史、核心负荷、价格和设备不变。返回新案例或原案例，不写文件，不宣称周期公平性。
"""
function r3_boundary_case(c::R2Case, boundary)
    boundary in (:legacy_tail, :bounded_return_tail, :core_only) ||
        throw(ArgumentError("未知边界对照"))
    haskey(c.data, "r3_mechanism") || throw(ArgumentError("边界对照须有冻结核心时段"))
    boundary!=:core_only && return c
    n=c.data["r3_mechanism"]["core_periods"]
    d=r3_core_data(c, n)
    d["id"] *= "-core-only"
    d["description"]*=" 仅核心时段诊断，不作公平周期收益比较。"
    d["r3_mechanism"]["tail_periods"]=0
    validate_r2_input(d)
    io=IOBuffer()
    TOML.print(io, d; sorted = true)
    return R2Case(d, bytes2hex(sha256(take!(io))))
end

function r3_core_signature(c, periods)
    d=r3_core_data(c, periods)
    for key in ("id", "description", "r3_mechanism")
        pop!(d, key, nothing)
    end
    io=IOBuffer()
    TOML.print(io, d; sorted = true)
    return bytes2hex(sha256(take!(io)))
end
