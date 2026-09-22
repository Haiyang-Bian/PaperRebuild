"""
    r7_normal_flow_spec(case; pipe_min, pipe_max, source_min, source_max, load_min, load_max,
                        thermal=:lossless, quadrature_order=10, max_truncation_error=1e-10)

建立R7-F1连续正向、零散热正常流量域；所有界为kg/s的管道/节点×时段矩阵，流量跨场景共享。
旧案例中的规定流量仅为输入载体，不是优化初值或新变量等式。输入、温区、初始空间分布、
电网与终端规则保持；原6-31的反向域仍未进入本版本。默认lossless拒绝非零UA；
显式thermal=:lossy_gauss使用R7-H1至H4的有损参考及误差契约，另存版本，不替换作者节点法。
正端口须有严格正下界，闲置端口上下界同为零，避免未定义的零流混合语义。
"""
function r7_normal_flow_spec(
    c::R7NormalCase;
    pipe_min,
    pipe_max,
    source_min,
    source_max,
    load_min,
    load_max,
    thermal = :lossless,
    quadrature_order = 10,
    max_truncation_error = 1e-10,
)
    thermal in (:lossless, :lossy_gauss) || error("未声明连续流量热模型")
    lossy = thermal == :lossy_gauss
    s=Dict{String,Any}(
        "schema"=>"r7-normal-flow-spec-v1",
        "case_sha256"=>c.sha256,
        "version"=>lossy ? "r7_continuous_positive_lossy_gauss_v1" :
                   "r7_continuous_positive_lossless_v1",
        "flow_unit"=>"kg/s",
        "scenario_rule"=>"shared_flows",
        "thermal_rule"=>lossy ? "mass_overlap_decay_gauss" : "exact_mass_overlap_zero_UA",
    )
    if lossy
        s["quadrature_order"] = quadrature_order
        s["max_truncation_error"] = Float64(max_truncation_error)
        s["bound_scope"] = "adopted_gauss_model_not_exact_PDE"
    end
    for (k, a) in (
        "pipe_min"=>pipe_min,
        "pipe_max"=>pipe_max,
        "source_min"=>source_min,
        "source_max"=>source_max,
        "load_min"=>load_min,
        "load_max"=>load_max,
    )
        s[k]=r7_pack(Float64.(a))
    end
    r7_normal_flow_check(c, s)
    s
end

r7_is_lossy_flow(s) = get(s, "version", "") == "r7_continuous_positive_lossy_gauss_v1"

function r7_normal_flow_check(c, s)
    r7_normal_assert(c)
    lossy = r7_is_lossy_flow(s)
    s["schema"]=="r7-normal-flow-spec-v1" &&
    s["case_sha256"]==c.sha256 &&
    s["version"] in
    ("r7_continuous_positive_lossless_v1", "r7_continuous_positive_lossy_gauss_v1") &&
    s["flow_unit"]=="kg/s" &&
    s["scenario_rule"]=="shared_flows" &&
    s["thermal_rule"]==(lossy ? "mass_overlap_decay_gauss" : "exact_mass_overlap_zero_UA") ||
        error("连续流量规格身份或范围错误")
    d=c.data
    h=d["heat"]
    T=d["periods"]
    d["thermal_model"]=="plug_flow_reference_v1" || error("不能将作者有损节点法静默换成无损塞流")
    lossy ||
        all(p["UA_$(side)_W_K"]==0 for p in h["pipes"] for side in ("S", "R")) ||
        error("本连续流量块尚未实现有损传播，不将UA隐式置零")
    if lossy
        s["quadrature_order"] in (5, 10) &&
        isfinite(s["max_truncation_error"]) &&
        0 < s["max_truncation_error"] <= 1e-10 &&
        s["bound_scope"] == "adopted_gauss_model_not_exact_PDE" || error("有损积分契约非法")
        for p in h["pipes"], side in ("S", "R")
            span = h["$(side)_max_K"]-h["$(side)_min_K"]
            ambient = (h["ambient_K"] .- h["$(side)_min_K"]) ./ span
            β =
                3600d["dt_h"]*p["UA_$(side)_W_K"]/(
                    h["rho_kg_m3"]*p["volume_$(side)_m3"]*h["c_J_kgK"]
                )
            error_bound = r7_loss_quadrature_bound(
                β,
                max(1, maximum(ambient))-min(0, minimum(ambient));
                order = s["quadrature_order"],
            )
            error_bound <= s["max_truncation_error"] || error("有损管积分截断界超出协议")
        end
    end
    b=Dict(
        k=>r7_unpack(s, k) for
        k in ("pipe_min", "pipe_max", "source_min", "source_max", "load_min", "load_max")
    )
    for (kind, cap) in (
        "pipe"=>[p["flow_max_kg_s"] for p in h["pipes"]],
        "source"=>h["source_flow_max"],
        "load"=>h["load_flow_max"],
    )
        lo, hi=b[kind*"_min"], b[kind*"_max"]
        size(lo)==size(hi)==(length(cap), T) && all(isfinite, lo) && all(isfinite, hi) ||
            error("流量界形状或有限性错误：$kind")
        all(0 .<= lo .<= hi .<= cap) || error("流量界越界：$kind")
        if kind=="pipe"
            all(>(0), lo) || error("连续正常分支暂不支持停流/反向")
        else
            all((lo .> 0) .| (hi .== 0)) || error("端口须声明正流或固定闲置")
            active=Float64.(reduce(hcat, h[kind*"_flow_kg_s"])') .> 0
            (lo .> 0)==active || error("本版本保持原源/荷端口活动集合")
        end
    end
    b
end

# 验证时建立明确的数值条件案例，不修改原输入，也不把其条件最优性界当自由流量的界。
function r7_normal_at_flow(c, flow; check_input = true)
    d=deepcopy(c.data)
    for (a, p) in enumerate(d["heat"]["pipes"])
        p["normal_flow_kg_s"]=collect(flow["pipe"][a, :])
    end
    for kind in ("source", "load")
        d["heat"][kind*"_flow_kg_s"]=[collect(flow[kind][j, :]) for j in axes(flow[kind], 1)]
    end
    check_input ? R7NormalCase(d) : R7NormalCase(d, r7_digest(d))
end
