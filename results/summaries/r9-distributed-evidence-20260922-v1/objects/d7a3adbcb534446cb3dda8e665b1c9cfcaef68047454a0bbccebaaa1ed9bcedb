"""
    R4DistributedSpec(; rho=1, peer_rho=1, max_iterations=1000, inner_iterations=100)

固定离散模式的第4章分布协调规则。归一化目标/通信量下的正罚系数固定不递增。
A4原始/对偶残差均1e-4；内层收紧至1e-7。它是由一致增广拉格朗日推导的
r4_atc_admm_checked_v1，不等同原文存在系数歧义的逐字算法；不支持整数/非凸收敛声明。
"""
struct R4DistributedSpec
    rho::Float64
    peer_rho::Float64
    max_iterations::Int
    inner_iterations::Int
    function R4DistributedSpec(;
        rho = 1.0,
        peer_rho = 1.0,
        max_iterations = 1000,
        inner_iterations = 100,
    )
        all(x->isfinite(x)&&x>0, (rho, peer_rho)) || error("罚系数须为有限正数")
        max_iterations isa Integer && max_iterations>0 || error("外层次数错误")
        inner_iterations isa Integer && inner_iterations>0 || error("内层次数错误")
        new(rho, peer_rho, max_iterations, inner_iterations)
    end
end

function r4_distributed_scales(c)
    a=c.data["actors"][2:3]
    P=max(
        0.1,
        maximum(
            max(
                x["CHP_max"]+x["PV_max"]+x["BS_power_max"],
                maximum(x["P_load"])*(1+x["flex"])+x["HP_max"]+x["EB_max"]+x["BS_power_max"],
            ) for x in a
        ),
    )
    Q=max(0.1, maximum(x["Q_ratio"]*maximum(x["P_load"])*(1+x["flex"]) for x in a))
    Hs=max(
        0.1,
        maximum(
            x["heat_ratio"]*x["CHP_max"]+x["COP_HP"]*x["HP_max"]+x["COP_EB"]*x["EB_max"] for x in a
        ),
    )
    Hd=max(0.1, maximum(maximum(x["H_load"])*(1+x["flex"]) for x in a))
    C=max(1.0, c.data["dt_h"]*maximum(c.data["grid_price"])*c.data["electric"]["grid_max"])
    return Dict("boundary"=>[P, Q, Hs, Hd], "peer"=>[P, max(Hs, Hd)], "cost"=>C)
end

function r4_distributed_options(spec)
    return Dict(
        "rho"=>spec.rho,
        "peer_rho"=>spec.peer_rho,
        "max_iterations"=>spec.max_iterations,
        "inner_iterations"=>spec.inner_iterations,
        "outer_tolerance"=>1e-4,
        "inner_tolerance"=>1e-7,
    )
end

# R4-D5：投影到q_A+q_B=0；u是无量纲缩放乘子，不是原式未定义尺度的λ。
function r4_peer_consensus(qA, qB, uA, uB)
    z=(qA+uA-qB-uB)/2
    return z, -z
end
