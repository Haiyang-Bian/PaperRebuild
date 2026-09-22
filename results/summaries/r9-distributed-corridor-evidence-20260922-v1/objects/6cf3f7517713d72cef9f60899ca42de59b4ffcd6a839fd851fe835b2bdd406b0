function r6_log_binomial_cdf(k, n, p)
    p == 0 && return 0.0
    p == 1 && return k == n ? 0.0 : -Inf
    term = n * log1p(-p)
    total = term
    # 对数域累计避免1000条及极端概率的下溢，不用正态近似替代A5。
    for j in 1:k
        term += log(n - j + 1) - log(j) + log(p) - log1p(-p)
        large, small = max(total, term), min(total, term)
        total = large + log1p(exp(small - large))
    end
    total
end

function r6_cp_upper(k, n, alpha)
    k == n && return 1.0
    k == 0 && return -expm1(log(alpha) / n)
    lo, hi = k / n, 1.0
    for _ in 1:80
        mid = (lo + hi) / 2
        (mid == lo || mid == hi) && break
        if r6_log_binomial_cdf(k, n, mid) > log(alpha)
            lo = mid
        else
            hi = mid
        end
    end
    hi
end

"""
    r6_binomial_bounds(k, n; confidence=0.95)

计算k次联合违约、n条独立轨迹的Clopper–Pearson单侧上下界，项目式R6-S3。
通过二项尾概率反演；返回的上下界各自为单侧confidence，不能称为同覆盖率双侧区间。
输入必须为0≤k≤n且n>0；极端计数解析处理。测试R6-CP包含独立高精度尾概率与覆盖检查。
"""
function r6_binomial_bounds(k::Integer, n::Integer; confidence = 0.95)
    0 <= k <= n && n > 0 || error("要求0≤k≤n且n>0")
    isfinite(confidence) && 0 < confidence < 1 || error("置信水平须在(0,1)")
    alpha = 1 - Float64(confidence)
    (
        lower = 1 - r6_cp_upper(n - k, n, alpha),
        upper = r6_cp_upper(k, n, alpha),
        confidence = Float64(confidence),
    )
end

"""
    r6_risk_evidence(events; epsilon, confidence=0.95)

按完整轨迹统计:pass、:violation、:unknown，项目式R6-S4。
未知仍在分母，下界按已知违约，上界将未知全部计为违约。只在U≤epsilon时支持，L>epsilon时拒绝。
事件应来自独立验证器；本函数不从求解器成功状态推断室温合格或备用交付。
结论仅适用于预声明独立采样分布；多个方法的比较不自动成为同时95%保证。
"""
function r6_risk_evidence(events; epsilon, confidence = 0.95)
    isfinite(epsilon) && 0 <= epsilon <= 1 || error("风险上限须在[0,1]")
    !isempty(events) && all(x -> x in (:pass, :violation, :unknown), events) ||
        error("轨迹事件缺失或分类未知")
    n, k, u = length(events), count(==(:violation), events), count(==(:unknown), events)
    lower = r6_binomial_bounds(k, n; confidence).lower
    upper = r6_binomial_bounds(k + u, n; confidence).upper
    Dict{String,Any}(
        "n" => n,
        "violations" => k,
        "unknown" => u,
        "passed" => n - k - u,
        "known_violation_fraction" => k / n,
        "conservative_violation_fraction" => (k + u) / n,
        "lower" => lower,
        "upper" => upper,
        "one_sided_confidence" => confidence,
        "epsilon" => epsilon,
        "sample_unit" => "complete_trajectory",
        "status" => upper <= epsilon ? "supported" : lower > epsilon ? "rejected" : "inconclusive",
    )
end

function r6_quantile(x, p)
    a = sort(x)
    t = 1 + (length(a) - 1) * p
    lo, hi = floor(Int, t), ceil(Int, t)
    a[lo] + (t - lo) * (a[hi] - a[lo])
end

"""
    r6_paired_costs(ids_a, costs_a, ids_b, costs_b; seed, replicates=2000, confidence=0.95)

同一冻结测试集的费用差A−B，按轨迹ID配对并以Julia Xoshiro显式种子自助抽样，项目式R6-S5。
费用单位USD，允许负净费用；不把不同时间范围或目标的费用自动视为可比。
缺失费用保留并返回incomplete_pairs，不删除失败轨迹生成总体费用排名或区间。
完整配对时给出均值差、百分位自助区间和原始差分位数；区间是统计估计，非确定性最优性界。
"""
function r6_paired_costs(ids_a, costs_a, ids_b, costs_b; seed, replicates = 2000, confidence = 0.95)
    length(ids_a) == length(costs_a) > 0 && length(ids_b) == length(costs_b) ||
        error("费用维度错误")
    length(unique(ids_a)) == length(ids_a) && length(unique(ids_b)) == length(ids_b) ||
        error("重复ID")
    Set(ids_a) == Set(ids_b) || error("费用必须来自完全相同的测试轨迹")
    all(x -> ismissing(x) || (x isa Real && isfinite(x)), vcat(costs_a, costs_b)) ||
        error("费用非有限")
    seed isa Integer && seed >= 0 && replicates isa Integer && replicates > 0 ||
        error("自助规则错误")
    isfinite(confidence) && 0 < confidence < 1 || error("置信水平错误")
    b = Dict(id => cost for (id, cost) in zip(ids_b, costs_b))
    delta = [
        ismissing(a) || ismissing(b[id]) ? missing : Float64(a - b[id]) for
        (id, a) in zip(ids_a, costs_a)
    ]
    all(x -> ismissing(x) || isfinite(x), delta) || error("费用差溢出")
    absent = count(ismissing, delta)
    result = Dict{String,Any}(
        "n" => length(delta),
        "missing_pairs" => absent,
        "unit" => "USD",
        "direction" => "A_minus_B",
        "seed" => seed,
        "replicates" => replicates,
        "confidence" => confidence,
        "status" => absent > 0 ? "incomplete_pairs" : "complete_pairs",
    )
    absent > 0 && return result
    x = Float64.(delta)
    rng = Random.Xoshiro(seed)
    means = [sum(x[rand(rng, 1:length(x))] for _ in eachindex(x)) / length(x) for _ in 1:replicates]
    tail = (1 - confidence) / 2
    merge!(
        result,
        Dict(
            "mean_difference" => sum(x) / length(x),
            "lower" => r6_quantile(means, tail),
            "upper" => r6_quantile(means, 1 - tail),
            "q10" => r6_quantile(x, 0.1),
            "median" => r6_quantile(x, 0.5),
            "q90" => r6_quantile(x, 0.9),
        ),
    )
end
