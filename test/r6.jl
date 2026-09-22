using Test, PaperRebuild, TOML

function r6_test_protocol()
    d = TOML.parsefile(joinpath(@__DIR__, "..", "configs", "r6", "protocol.toml"))
    d["T"], d["dt_h"] = 2, 12.0
    d["generator"]["clear_sky_fraction"] = [0.0, 1.0]
    d["samples"]["train"], d["samples"]["validation"] = 12, 3
    d["clustering"]["count"] = 2
    R6Protocol(d)
end

@testset "R6-SPLIT complete-day and leakage guards" begin
    p = r6_test_protocol()
    sets = Dict(s => r6_generate_trajectories(p, s) for s in ("train", "validation", "test"))
    @test size(sets["test"].values) == (2, 2, 1000)
    @test r6_generate_trajectories(p, "train").sha256 == sets["train"].sha256
    @test all(iszero, sets["train"].values[1, 1, :])
    @test all(x -> 0 <= x <= 1, sets["train"].values[1, :, :])
    @test all(x -> -1 <= x <= 1, sets["test"].values[2, :, :])
    @test isempty(intersect(sets["train"].ids, sets["test"].ids))
    @test_throws ErrorException r6_fit_representatives(sets["test"], p)
    @test_throws ErrorException r6_fit_representatives(sets["validation"], p)
    @test_throws ErrorException r6_generate_trajectories(p, "holdout")
    for change in (
        d -> d["samples"]["test"] = 999,
        d -> d["dt_h"] = 1.0,
        d -> d["seeds"]["test"] = d["seeds"]["train"],
        d -> d["methods"] = ["DRJCC"],
        d -> d["generator"]["weather_ar"] = 1.0,
        d -> d["statistics"]["unknown_rule"] = "drop",
    )
        d = deepcopy(p.data)
        change(d)
        @test_throws ErrorException R6Protocol(d)
    end
    s = deepcopy(sets["train"])
    s.values[1, 2, 1] = 0.0
    @test_throws ErrorException r6_fit_representatives(s, p)
    @test_throws ErrorException R6TrajectorySet(
        "train",
        fill("train_1", 2),
        zeros(2, 2, 2),
        p.sha256,
    )
end

@testset "R6-CLUSTER exact separated groups and immutable replay" begin
    p = r6_test_protocol()
    values = zeros(2, 2, 12)
    values[1, :, 1:6] .= 0.1
    values[1, :, 7:12] .= 0.9
    s = R6TrajectorySet("train", ["train_" * lpad(i, 6, '0') for i in 1:12], values, p.sha256)
    r = r6_fit_representatives(s, p)
    @test r["converged"]
    @test r["counts"] == [6, 6]
    @test r["probabilities"] == [0.5, 0.5]
    @test Set(r["representative_indices"]) == Set([1, 7])
    @test r["within_cluster_sse"] < 1e-28
    distance = r6_support_distance(s, r)
    @test distance[1, 2] ≈ 0.8 / sqrt(2)
    @test distance[1, 1] == 0 && distance == transpose(distance)
    duplicate = R6TrajectorySet("train", s.ids, zeros(2, 2, 12), p.sha256)
    @test_throws ErrorException r6_fit_representatives(duplicate, p)
    sets = Dict(
        split => r6_generate_trajectories(p, split) for split in ("train", "validation", "test")
    )
    reps = r6_fit_representatives(sets["train"], p)
    mktempdir() do tmp
        path = joinpath(tmp, "frozen")
        save_r6_dataset(path, p, sets, reps)
        replay = read_r6_dataset(path)
        @test replay.protocol.sha256 == p.sha256
        @test replay.sets["test"].values == sets["test"].values
        @test replay.representatives == reps
        @test_throws ErrorException save_r6_dataset(path, p, sets, reps)
        file = joinpath(path, "test-001.csv")
        open(file, "a") do io
            write(io, "\n")
        end
        @test_throws ErrorException read_r6_dataset(path)
    end
end

@testset "R6-CP analytic extremes and independent binomial probabilities" begin
    for n in (1, 10, 1000)
        @test r6_binomial_bounds(0, n).lower == 0.0
        @test r6_binomial_bounds(0, n).upper ≈ 1 - 0.05^(1 / n) atol = 1e-14
        @test r6_binomial_bounds(n, n).upper == 1.0
        @test r6_binomial_bounds(n, n).lower ≈ 0.05^(1 / n) atol = 1e-14
    end
    # 独立BigFloat/BigInt组合数计算；不复用实现中的对数递推或二分。
    setprecision(256) do
        for (k, n) in ((1, 10), (5, 10), (1, 1000), (50, 1000), (950, 1000), (999, 1000))
            bound = r6_binomial_bounds(k, n)
            p = BigFloat(bound.upper)
            tail = sum(BigFloat(binomial(big(n), j)) * p^j * (1 - p)^(n - j) for j in 0:k)
            @test abs(tail - big"0.05") < big"1e-10"
            @test bound.lower ≈ 1 - r6_binomial_bounds(n - k, n).upper atol = 1e-14
        end
    end
    # 小n穷举所有计数，分别检查上下单侧覆盖，而非误称共同双侧95%。
    for n in 1:12, p in 0.05:0.1:0.95
        bounds = [r6_binomial_bounds(k, n) for k in 0:n]
        pmf = [binomial(n, k) * p^k * (1 - p)^(n - k) for k in 0:n]
        @test sum(pmf[i] for i in eachindex(bounds) if bounds[i].upper >= p) >= 0.95 - 1e-12
        @test sum(pmf[i] for i in eachindex(bounds) if bounds[i].lower <= p) >= 0.95 - 1e-12
    end
    @test_throws ErrorException r6_binomial_bounds(0, 0)
    @test_throws ErrorException r6_binomial_bounds(-1, 10)
    @test_throws ErrorException r6_binomial_bounds(11, 10)
    @test_throws ErrorException r6_binomial_bounds(1, 10; confidence = 1.0)
end

@testset "R6-UNKNOWN no failed trajectory disappears" begin
    @test r6_risk_evidence(fill(:pass, 1000); epsilon = 0.05)["status"] == "supported"
    @test r6_risk_evidence(vcat(fill(:violation, 100), fill(:pass, 900)); epsilon = 0.05)["status"] ==
          "rejected"
    uncertain = r6_risk_evidence(
        vcat(fill(:violation, 30), fill(:unknown, 50), fill(:pass, 920));
        epsilon = 0.05,
    )
    @test uncertain["status"] == "inconclusive"
    @test uncertain["n"] == 1000 && uncertain["unknown"] == 50
    @test uncertain["lower"] == r6_binomial_bounds(30, 1000).lower
    @test uncertain["upper"] == r6_binomial_bounds(80, 1000).upper
    @test r6_risk_evidence(fill(:unknown, 1000); epsilon = 0.05)["upper"] == 1.0
    @test_throws ErrorException r6_risk_evidence([:solver_success]; epsilon = 0.05)
    @test_throws ErrorException r6_risk_evidence(Symbol[]; epsilon = 0.05)
end

@testset "R6-PAIR paired cost and missingness" begin
    a, b = ["one", "two", "three"], ["three", "one", "two"]
    r = r6_paired_costs(a, [10.0, 20.0, 30.0], b, [25.0, 5.0, 15.0]; seed = 23)
    @test r["mean_difference"] == r["lower"] == r["upper"] == 5.0
    @test r == r6_paired_costs(a, [10.0, 20.0, 30.0], b, [25.0, 5.0, 15.0]; seed = 23)
    r = r6_paired_costs(a, [10.0, missing, 30.0], b, [25.0, 5.0, 15.0]; seed = 23)
    @test r["status"] == "incomplete_pairs" && r["missing_pairs"] == 1 && r["n"] == 3
    @test !haskey(r, "mean_difference") && !haskey(r, "lower")
    @test_throws ErrorException r6_paired_costs(
        a,
        [1, 2, 3],
        ["one", "two", "four"],
        [1, 2, 3];
        seed = 1,
    )
    @test_throws ErrorException r6_paired_costs(a, [1, Inf, 3], b, [1, 2, 3]; seed = 1)
end
