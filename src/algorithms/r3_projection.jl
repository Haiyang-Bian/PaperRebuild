function r3_flow_box(c, operation = nothing)
    pipes, T = c.data["heat"]["pipes"], c.data["T"]
    lo = repeat(reshape([p["flow_min"] for p in pipes], :, 1), 1, T)
    hi = repeat(reshape([p["flow_max"] for p in pipes], :, 1), 1, T)
    if !isnothing(operation)
        for p in eachindex(pipes), t in 1:T
            if r3_is_cf(operation) || t>operation.core_periods
                lo[p, t]=hi[p, t]=operation.reference_flow[p]
            end
        end
    end
    return lo, hi, hi-lo
end

# 数值回代复用既有独立电/水力核；仅忽略本投影明确删除的热关系。
function r3_projection_witness(c, values; operation = nothing)
    result=Dict{String,Any}(
        "input_sha256"=>c.sha256,
        "values"=>values,
        "spec"=>r2_spec_dict(R2Spec()),
        "fixed_flows"=>false,
        "objective"=>r3_operating_cost(c, values),
    )
    if !isnothing(operation)
        result["operation"]=r3_operation_dict(operation)
        result["operation_sha256"]=r3_operation_hash(result["operation"])
    end
    report=validate_r2_solution(c, result)
    omitted=("3-17", "3-27", "3-28", "3-30", "3-31", "3-33:34", "3-35:36")
    return all(r.pass for r in report.rows if r.scope=="model" && !(r.equation in omitted))
end

"""
    build_r3_projection(case, target; center=nothing, gradient=nothing, violation=0.0, radius=0.1, optimizer=nothing)

式3-63/66采用解释：在凸主问题外松弛域中最小化归一化流量到target(kg/s)的平方距离。
调度辅助变量同时优化；移除3-17、3-27/28/30/31/33/34/35/36热耦合，保留设备、
电网、水力锥、温度边界和质量守恒。可选局部半空间仅供单次试探，不能永久切除可行域。
gradient为归一化坐标中的诊断梯度；不求解、不写文件。距离使用二阶锥上图表示。
geometry默认normalized_euclidean保持旧行为；physical_euclidean直接使用kg/s距离。
"""
function build_r3_projection(
    c::R2Case,
    target;
    center = nothing,
    gradient = nothing,
    violation = 0.0,
    radius = 0.1,
    optimizer = nothing,
    operation = nothing,
    geometry = :normalized_euclidean,
)
    geometry in (:physical_euclidean, :normalized_euclidean) || throw(ArgumentError("未知投影几何"))
    lo, hi, width = r3_flow_box(c, operation)
    size(target)==size(lo) && all(isfinite, target) ||
        throw(ArgumentError("投影目标形状/有限值错误"))
    b=build_r2_model(c; optimizer, operation)
    removed=["3-17", "3-27", "3-28", "3-30", "3-31", "3-33", "3-34", "3-35", "3-36"]
    for id in removed
        for cr in get(b.constraints, id, Any[])
            delete(b.model, cr)
        end
        delete!(b.constraints, id)
    end
    m=b.variables["m_pipe"]
    delta=AffExpr[]
    for i in eachindex(lo)
        if width[i]==0
            fix(m[i], lo[i]; force = true)
        else
            push!(delta, (m[i]-target[i])/(geometry==:physical_euclidean ? 1.0 : width[i]))
        end
    end
    if !isnothing(gradient)
        !isnothing(center) &&
        size(center)==size(lo) &&
        size(gradient)==size(lo) &&
        all(isfinite, center) &&
        all(isfinite, gradient) &&
        isfinite(violation) &&
        violation>=0 &&
        0<radius<=1 || throw(ArgumentError("非法局部试探数据"))
        expr=AffExpr(violation)
        for i in eachindex(lo)
            width[i]>0 || continue
            z=(m[i]-center[i])/width[i]
            add_to_expression!(expr, gradient[i]*z)
            @constraint(b.model, z<=radius)
            @constraint(b.model, z>=-radius)
        end
        @constraint(b.model, expr<=0)
    end
    epigraph=@variable(b.model, lower_bound=0)
    @constraint(b.model, [epigraph+1; 2 .* delta; epigraph-1] in SecondOrderCone())
    @objective(b.model, Min, epigraph)
    r2_model_class(b.model)=="SOCP" || error("投影域中残留非凸/整数关系")
    return merge(
        b,
        (;
            class = "SOCP",
            removed,
            target = copy(target),
            width,
            center,
            gradient,
            violation,
            radius,
            geometry,
        ),
    )
end

function r3_project(c, target, optimizer; deadline = Inf, kwargs...)
    started=r3_clock()
    out=Dict{String,Any}("status"=>"not_run_solver", "target"=>r2_extract(target))
    isnothing(optimizer) && return out
    deadline>started || return merge(out, Dict("status"=>"budget_exhausted"))
    b=build_r3_projection(c, target; kwargs...)
    try
        set_optimizer(b.model, optimizer)
        set_silent(b.model)
        if occursin("Clarabel", solver_name(b.model))
            for key in ("tol_gap_abs", "tol_gap_rel", "tol_feas")
                set_optimizer_attribute(b.model, key, 1e-9)
            end
        end
        remaining=min(60.0, deadline-r3_clock())
        remaining>0 || return merge(out, Dict("status"=>"budget_exhausted"))
        set_time_limit_sec(b.model, remaining)
        optimize!(b.model)
        out["termination"]=string(termination_status(b.model))
        out["status"]=termination_status(b.model)==MOI.INFEASIBLE ? "projection_infeasible" :
                      "projection_unresolved"
        if termination_status(b.model)==MOI.OPTIMAL && has_values(b.model)
            m=value.(b.variables["m_pipe"])
            # 不修剪求解器输出；既有输入检查独立检验边界与守恒。
            r2_flow_matrix(c, m)
            violations=primal_feasibility_report(b.model; atol = 1e-6)
            if isempty(violations)
                out["status"]="projected"
                out["flow"]=r2_extract(m)
                out["values"]=Dict(k=>r2_extract(v) for (k, v) in b.variables)
                out["distance"]=sum(
                    ((m[i]-target[i])/(b.geometry==:physical_euclidean ? 1.0 : b.width[i]))^2 for
                    i in eachindex(m) if b.width[i]>0;
                    init = 0.0,
                )
                out["constraint_violation"]=0.0
                out["geometry"]=string(b.geometry)
                out["removed_equations"]=b.removed
                out["local_halfspace"]=!isnothing(b.gradient)
                if !isnothing(b.gradient)
                    out["center"]=r2_extract(b.center)
                    out["gradient"]=r2_extract(b.gradient)
                    out["violation"]=b.violation
                    out["radius"]=b.radius
                end
            end
        end
    catch err
        if err isa Union{MOI.UnsupportedConstraint,MOI.UnsupportedAttribute}
            out["status"]="unsupported_solver"
        elseif occursin("license", lowercase(sprint(showerror, err)))
            out["status"]="not_run_license"
        else
            rethrow()
        end
    end
    out["elapsed_sec"]=r3_clock()-started
    return out
end
