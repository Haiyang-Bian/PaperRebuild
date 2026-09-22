"""
    r6_generate_trajectories(protocol, split)

按显式分组种子生成完整日PV/调用轨迹，不求解模型，项目式R6-S2。
每天重新抽取平稳AR初始状态与日云量；各时段相关，各日由独立随机抽取构成。
PV比例为晴空曲线乘有界云量映射，调用为tanh映射；这是假设生成分布，不是作者历史数据。
使用Julia Random.Xoshiro，最终数值必须冻结，不能只靠种子承诺跨Julia版本逐位复现。
"""
function r6_generate_trajectories(p::R6Protocol, split::AbstractString)
    r6_assert_protocol(p)
    split in R6_SPLITS || error("未知数据分组")
    d, g = p.data, p.data["generator"]
    rng = Random.Xoshiro(d["seeds"][split])
    T, n = d["T"], d["samples"][split]
    values = zeros(2, T, n)
    rho_w, rho_a = g["weather_ar"], g["activation_ar"]
    for i in 1:n
        daily, weather, activation = randn(rng), randn(rng), randn(rng)
        for t in 1:T
            weather = rho_w * weather + sqrt(1 - rho_w^2) * randn(rng)
            activation = rho_a * activation + sqrt(1 - rho_a^2) * randn(rng)
            z =
                g["cloud_intercept"] +
                g["cloud_daily_scale"] * daily +
                g["cloud_hourly_scale"] * weather
            cloud = z >= 0 ? 1 / (1 + exp(-z)) : exp(z) / (1 + exp(z))
            values[1, t, i] = g["clear_sky_fraction"][t] * cloud
            values[2, t, i] = tanh(g["call_scale"] * activation)
        end
    end
    R6TrajectorySet(split, [split * "_" * lpad(i, 6, '0') for i in 1:n], values, p.sha256)
end

function r6_features(values)
    x = reshape(copy(values), 2 * size(values, 2), size(values, 3))
    x[2:2:end, :] ./= 2 # [-1,1]调用跨度为2；PV跨度为1。尺度不从测试集估计。
    x ./ sqrt(size(x, 1))
end

function r6_distance2(x, i, centers, j)
    value = 0.0
    for f in axes(x, 1)
        value += (x[f, i] - centers[f, j])^2
    end
    value
end

function r6_nearest(x, i, centers)
    best, dist = 1, r6_distance2(x, i, centers, 1)
    for j in 2:size(centers, 2)
        trial = r6_distance2(x, i, centers, j)
        if trial < dist
            best, dist = j, trial
        end
    end
    best
end

"""
    r6_fit_representatives(training, protocol)

只使用train完整轨迹做确定性Lloyd k-means，项目式R6-S6。
最远点初始化；等距取最早索引。每簇以距中心最近的原始训练轨迹为代表，权重为簇频数。
选原始轨迹保持同一时段上下调用互斥；不能将其冒称作者未公开的中心/权重选择规则。
返回中心、分配、代表ID、概率及停止证据；未收敛或空簇不能封存为已完成聚类。
"""
function r6_fit_representatives(s::R6TrajectorySet, p::R6Protocol)
    r6_assert_protocol(p)
    r6_assert_set(s)
    s.split == "train" || error("验证/测试集不得进入聚类拟合")
    s.protocol_sha256 == p.sha256 && length(s.ids) == p.data["samples"]["train"] ||
        error("训练身份不符")
    size(s.values, 2) == p.data["T"] || error("训练时域不符")
    x = r6_features(s.values)
    n, k = length(s.ids), p.data["clustering"]["count"]
    mean_x = sum(x; dims = 2) ./ n
    chosen = [argmin([r6_distance2(x, i, mean_x, 1) for i in 1:n])]
    distances = [r6_distance2(x, i, x, first(chosen)) for i in 1:n]
    while length(chosen) < k
        i = argmax(distances)
        distances[i] > 0 || error("不同训练轨迹不足以形成指定簇数")
        push!(chosen, i)
        for a in 1:n
            distances[a] = min(distances[a], r6_distance2(x, a, x, i))
        end
    end
    centers, labels, counts = x[:, chosen], zeros(Int, n), zeros(Int, k)
    converged, iterations = false, 0
    for iteration in 1:p.data["clustering"]["max_iterations"]
        next = [r6_nearest(x, i, centers) for i in 1:n]
        fill!(counts, 0)
        updated = zeros(size(centers))
        for i in 1:n
            counts[next[i]] += 1
            for f in axes(x, 1)
                updated[f, next[i]] += x[f, i]
            end
        end
        all(>(0), counts) || error("出现空簇；不静默减少代表数")
        updated ./= reshape(counts, 1, k)
        shift = maximum(abs.(updated .- centers))
        same = next == labels
        labels, centers, iterations = next, updated, iteration
        if same || shift <= p.data["clustering"]["tolerance"]
            converged = all(r6_nearest(x, i, centers) == labels[i] for i in 1:n)
            converged && break
        end
    end
    representatives = [
        begin
            members = findall(==(j), labels)
            members[argmin([r6_distance2(x, i, centers, j) for i in members])]
        end for j in 1:k
    ]
    Dict{String,Any}(
        "schema" => "r6-representatives-v1",
        "protocol_sha256" => p.sha256,
        "training_sha256" => s.sha256,
        "fitted_split" => "train",
        "converged" => converged,
        "iterations" => iterations,
        "labels" => labels,
        "counts" => counts,
        "probabilities" => counts ./ n,
        "representative_indices" => representatives,
        "representative_ids" => s.ids[representatives],
        "normalized_centers" => [collect(centers[:, j]) for j in 1:k],
        "within_cluster_sse" => sum(r6_distance2(x, i, centers, labels[i]) for i in 1:n),
    )
end

"""
    r6_support_distance(training, representatives)

返回冻结代表轨迹之间的归一化RMS距离矩阵，项目式R6-S6。
整条PV与调用轨迹共同构成距离；不能用测试轨迹替换支持点或据测试表现选择半径。
该有限支持距离不自动提供连续未知分布上的风险保证。
"""
function r6_support_distance(s::R6TrajectorySet, reps)
    r6_assert_set(s)
    s.split == "train" && reps["training_sha256"] == s.sha256 || error("代表集来源错误")
    ids = Int.(reps["representative_indices"])
    !isempty(ids) && length(unique(ids)) == length(ids) && all(i -> 1 <= i <= length(s.ids), ids) ||
        error("代表索引错误")
    reps["representative_ids"] == s.ids[ids] || error("代表身份与索引不符")
    x = r6_features(s.values)
    [sqrt(r6_distance2(x, i, x, j)) for i in ids, j in ids]
end
