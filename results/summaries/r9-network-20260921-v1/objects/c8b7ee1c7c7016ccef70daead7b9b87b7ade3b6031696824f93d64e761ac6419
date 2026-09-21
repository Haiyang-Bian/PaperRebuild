"""
    validate_r4_allocation(allocation)

从输入效用、支付及分配数值独立重算预算平衡、个体理性、剩余恒等式与
加权Nash一阶条件。金额容差沿用1e-6×输入尺度，无量纲条件为1e-6。
负剩余记录可正确但不存在合格分配；record_pass和allocation_pass分别报告。
不读取物理模型状态，物理通过须由上层r4_allocate_coordination另行验收。
"""
function validate_r4_allocation(r)
    u=Float64.(r["prepayment_utility"])
    d=Float64.(r["disagreement_utility"])
    w=Float64.(r["weights"])
    n=length(u)
    length(d)==length(w)==n>=2 || error("议价记录维度错误")
    all(isfinite, vcat(u, d, w)) && all(>(0), w) || error("议价记录输入非法")
    S=sum(u)-sum(d)
    scale=max(1.0, maximum(abs, u), maximum(abs, d))
    tol=1e-6*scale
    rows=Dict{String,Any}[]
    function check(id, residual, tolerance)
        push!(
            rows,
            Dict(
                "equation"=>id,
                "residual"=>residual,
                "tolerance"=>tolerance,
                "pass"=>isfinite(residual)&&residual<=tolerance,
            ),
        )
    end
    check("R4-N1-surplus", abs(r["surplus"]-S), tol)
    fractions=w ./ sum(w)
    check("R4-N1-weights", maximum(abs.(fractions .- r["weight_fractions"])), 1e-6)
    expected=sum(u .- d)<0 ? "negative_surplus" :
             sum(u .- d)==0 ? "zero_surplus_degenerate" : "allocated"
    check("R4-N1-status", r["status"]==expected ? 0.0 : 1.0, 0.0)
    fields=("gain", "total_transfer", "utility_after")
    if expected=="negative_surplus"
        check("R4-N1-no-fictitious-transfer", any(haskey(r, k) for k in fields) ? 1.0 : 0.0, 0.0)
    else
        all(haskey(r, k) && length(r[k])==n for k in fields) || error("缺少完整分配")
        p=Float64.(r["total_transfer"])
        actual=u .+ p
        gains=actual .- d
        check("4-73-budget", abs(sum(p)), tol)
        check("4-72-individual-rationality", max(0.0, -minimum(gains)), tol)
        check("R4-N1-gain-identity", abs(sum(gains)-S), tol)
        check("R4-N1-gain-record", maximum(abs.(gains .- r["gain"])), tol)
        check("R4-N1-utility-record", maximum(abs.(actual .- r["utility_after"])), tol)
        # (4-80)等价比例条件，直接检验增益与权重，不再次调用解析分配器。
        if expected=="allocated"
            check("4-80-positive-gain", minimum(gains)>0 ? 0.0 : 1.0, 0.0)
            check("4-80-weighted-stationarity", maximum(abs.(gains ./ S .- fractions)), 1e-6)
            logvalue=all(>(0), gains) ? sum(fractions .* log.(gains)) : NaN
            check(
                "4-78-objective",
                abs(get(r, "log_nash", NaN)-logvalue),
                1e-6*max(1.0, abs(logvalue)),
            )
        else
            check("R4-N1-zero-gain", maximum(abs, gains), tol)
            check("R4-N1-no-log-zero", haskey(r, "log_nash") ? 1.0 : 0.0, 0.0)
        end
    end
    passed=all(x["pass"] for x in rows)
    return Dict(
        "record_pass"=>passed,
        "allocation_pass"=>passed&&expected!="negative_surplus",
        "strict_improvement"=>passed&&expected=="allocated",
        "rows"=>rows,
    )
end
