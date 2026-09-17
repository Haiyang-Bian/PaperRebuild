"""
    R3OperationSpec(case; mode=:VF_VT, core_periods=case.data["T"], bounded_return=true)

四模式控制约定。CF固定各管恒定参考流量；CT只固定热源端口供水温度。
参考值来自输入fixed_flow首值和S_reference_K，拒绝非恒定参考计划。
核心时段后统一固定参考流量、源温度和负荷回水温度，恢复初始稳态。
bounded_return只改变显式传入此约定的新运行；旧R2/R3调用仍固定负荷回水温度。
单位：kg/s、K；core_periods与恢复尾段长度是时间步数。
"""
struct R3OperationSpec
    mode::Symbol
    core_periods::Int
    reference_flow::Vector{Float64}
    source_temperature_K::Float64
    bounded_return::Bool
end

function R3OperationSpec(
    c::R2Case;
    mode = :VF_VT,
    core_periods = get(get(c.data, "r3_mechanism", Dict()), "core_periods", c.data["T"]),
    bounded_return = true,
)
    mode in (:CF_CT, :CF_VT, :VF_CT, :VF_VT) || throw(ArgumentError("未知四模式"))
    1<=core_periods<=c.data["T"] || throw(ArgumentError("核心时段非法"))
    pipes=c.data["heat"]["pipes"]
    all(maximum(abs.(p["fixed_flow"] .- first(p["fixed_flow"])))<=1e-12 for p in pipes) ||
        throw(ArgumentError("四模式参考流量必须恒定"))
    return R3OperationSpec(
        mode,
        core_periods,
        [first(p["fixed_flow"]) for p in pipes],
        c.data["heat"]["S_reference_K"],
        bounded_return,
    )
end

r3_operation_dict(o::R3OperationSpec) = Dict{String,Any}(
    "mode"=>string(o.mode),
    "core_periods"=>o.core_periods,
    "reference_flow"=>o.reference_flow,
    "source_temperature_K"=>o.source_temperature_K,
    "bounded_return"=>o.bounded_return,
)
function r3_operation_from_dict(d)
    return R3OperationSpec(
        Symbol(d["mode"]),
        Int(d["core_periods"]),
        Float64.(d["reference_flow"]),
        Float64(d["source_temperature_K"]),
        Bool(d["bounded_return"]),
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
            elseif n["role"]=="load" && tail
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
            elseif n["role"]=="load" && tail
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
