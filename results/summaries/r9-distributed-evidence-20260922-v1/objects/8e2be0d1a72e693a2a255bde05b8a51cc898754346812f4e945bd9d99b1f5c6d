"""
    validate_r4_distributed(case, result)

从保存通信量独立回算ADMM原始/对偶残差、缩放乘子递推及内层反对称投影。
从各主体保存控制重新合并，再调用独立物理/合同验证；不使用JuMP表达式或集中解。
返回记录一致性、A4停止、采用模型A1和原电网等式四项；局部增广目标界不是社会费用界。
"""
function validate_r4_distributed(c::R4Case, r)
    r["schema"]=="r4-distributed-run-v1" && r["input_sha256"]==c.sha256 ||
        error("分布输入/版本不匹配")
    r["scales"]==r4_distributed_scales(c) || error("冻结尺度改变")
    opts=r["options"]
    rho=opts["rho"]
    prho=opts["peer_rho"]
    T=c.data["T"]
    match(a, b) =
        size(a)==size(b) &&
        all(isfinite, a) &&
        all(isfinite, b) &&
        maximum(abs, a-b; init = 0.0)<=1e-10
    oldz=zeros(8, T)
    oldu=zeros(8, T)
    for (k, row) in enumerate(r["trace"])
        row["iteration"]==k || error("外层顺序改变")
        x, z, u=(r4_matrix(row[key]) for key in ("x", "z", "u"))
        match(u, oldu+x-z) || error("外层乘子递推错误")
        abs(maximum(abs, x-z)-row["primal"])<=1e-12 || error("外层原始残差改变")
        abs(rho*maximum(abs, z-oldz)-row["dual"])<=1e-12 || error("外层对偶残差改变")
        oldz, oldu=z, u
    end
    qold=[zeros(2, T), zeros(2, T)]
    uold=[zeros(2, T), zeros(2, T)]
    for row in r["inner_trace"]
        q=[r4_matrix(x) for x in row["q"]]
        z=[r4_matrix(x) for x in row["z"]]
        u=[r4_matrix(x) for x in row["u"]]
        # 独立使用约束q_A+q_B=0的最小二乘解，不调用求解端投影函数。
        expected=(q[1]+uold[1]-q[2]-uold[2])/2
        match(z[1], expected) && match(z[2], -expected) || error("反对称投影错误")
        all(match(u[j], uold[j]+q[j]-z[j]) for j in 1:2) || error("内层乘子递推错误")
        abs(maximum(maximum(abs, q[j]-z[j]) for j in 1:2)-row["primal"])<=1e-12 ||
            error("内层原始残差改变")
        abs(prho*maximum(maximum(abs, z[j]-qold[j]) for j in 1:2)-row["dual"])<=1e-12 ||
            error("内层对偶残差改变")
        qold, uold=z, u
    end
    model=false
    physical=false
    cost=NaN
    if haskey(r, "candidate")
        purpose=Symbol(r["purpose"])
        for a in r["agents"]
            i=a["actor"]
            s=a["values"]
            expected=zeros(4, T)
            for t in 1:T
                expected[1, t]=s["P_CHP"][i][t]+s["P_PV"][i][t]+s["P_dis"][i][t]-s["P_ch"][i][t]-s["P_HP"][i][t]-s["P_EB"][i][t]-s["P_D"][i][t]
                expected[2, t]=c.data["actors"][i]["Q_ratio"]*s["P_D"][i][t]
                expected[3, t]=s["H_src"][i][t]
                expected[4, t]=s["H_D"][i][t]
            end
            match(expected, r4_matrix(a["message"])) || error("局部消息不是实际控制边界")
            match(r4_matrix(s["peer"]), r4_matrix(a["peer"])) || error("局部合同消息改变")
            if c.data["actors"][i]["BS_power_max"]>0
                maximum(abs, s["z"]-r["modes"])<=1e-6 || error("冻结电池模式改变")
            end
        end
        candidate=r4_distributed_candidate(c, r["agents"], get(r, "operator", nothing), purpose)
        isequal(candidate, r["candidate"]) || error("主体控制/合并候选改变")
        model=candidate["validation"]["model_pass"]
        physical=purpose==:swm && model && candidate["validation"]["electric_original_pass"]
        cost=candidate["operating_cost"]
        if purpose==:swm && !isempty(r["trace"])
            s=r["operator"]["values"]
            expected=[
                s[("P_interface", "Q_interface", "Hs_interface", "Hd_interface")[mod1(k, 4)]][div(
                    k-1,
                    4,
                )+1][t] for k in 1:8, t in 1:T
            ]
            match(expected, r4_matrix(r["operator"]["message"])) ||
                error("网络消息不是实际边界副本")
            x=vcat((r4_normalized_message(a, r["scales"]) for a in r["agents"])...)
            match(x, r4_matrix(last(r["trace"])["x"])) || error("末次边界消息改变")
            match(
                r4_normalized_message(r["operator"], r["scales"]),
                r4_matrix(last(r["trace"])["z"]),
            ) || error("运营商消息改变")
        end
    end
    rows=r["purpose"]=="swm" ? r["trace"] : r["inner_trace"]
    a4=!isempty(rows) && last(rows)["primal"]<=1e-4 && last(rows)["dual"]<=1e-4
    r["status"]=="consensus_converged" && !(a4&&model) && error("停止状态证据不足")
    return Dict(
        "record_pass"=>true,
        "consensus_A4_pass"=>a4,
        "model_pass"=>model,
        "electric_original_pass"=>physical,
        "operating_cost"=>cost,
        "outer_iterations"=>length(r["trace"]),
        "inner_iterations"=>length(r["inner_trace"]),
        "central_cost_comparison_performed"=>false,
    )
end
