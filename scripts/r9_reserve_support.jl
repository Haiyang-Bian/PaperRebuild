module R9ReserveSupport
"""
    single_event_bound(probabilities, distance, radius, event)

在已冻结有限支持上，独立计算仅一个情景发生舒适事件时的最坏概率。
每个来源概率向该事件转移的单位代价是对应距离；按代价升序填充运输预算。
这是连续分数背包的解析解，不运行优化器、不读取费用或重新选择半径。
只有当所得上界不超过epsilon时，该单点事件才可能被联合风险约束允许。
"""
function single_event_bound(p, D, radius, event)
    n=length(p)
    size(D)==(n, n) && 1<=event<=n || error("Invalid support shape")
    all(isfinite, p) && minimum(p)>=0 && abs(sum(p)-1)<=1e-8 || error("Invalid probabilities")
    all(isfinite, D) && minimum(D)>=0 && isfinite(radius) && radius>=0 ||
        error("Invalid transport data")
    abs(D[event, event])<=1e-12 || error("Nonzero self distance")
    q=p[event]
    remaining=radius
    for j in sortperm(D[event, :])
        j==event && continue
        flow=D[event, j]==0 ? p[j] : min(p[j], remaining/D[event, j])
        q+=flow
        remaining=max(0.0, remaining-D[event, j]*flow)
    end
    min(1.0, q)
end
end
