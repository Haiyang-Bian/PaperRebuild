using Test, JuMP, Clarabel, TOML, SHA

# R5-Q05-1/2：每一列为完整情景，每一行为指定时空约束；联合违约使用“至少一个”。
"""将约束×情景的布尔越界矩阵转为每个情景的联合违约0/1指示。"""
joint_violation(v::AbstractMatrix{Bool}) = Int.(vec(any(v; dims = 1)))

"""
概率运输手算审计：经验权重、有限距离、0/1违约指示和半径给定，
分别求解原LP与独立对偶，返回概率、运输质量、乘子和直接残差。
仅用于R5-Q05解析检查，不是尚未实现的完整第5章调度接口。
"""
function probability_oracle(weights, distance, z, radius)
    n=length(weights)
    size(distance)==(n, n) && length(z)==n || error("概率运输维度错误")
    all(isfinite, weights) && all(weights .>= 0) && isapprox(sum(weights), 1; atol = 1e-12) ||
        error("经验概率错误")
    all(isfinite, distance) && all(distance .>= 0) && all(distance[i, i]==0 for i in 1:n) ||
        error("运输距离错误")
    isfinite(radius)&&radius>=0 && all(x->x in (0, 1), z) || error("半径/指示量错误")
    function solver()
        m=Model(
            optimizer_with_attributes(
                Clarabel.Optimizer,
                "tol_feas"=>1e-10,
                "tol_gap_abs"=>1e-10,
                "tol_gap_rel"=>1e-10,
            ),
        )
        set_silent(m)
        set_time_limit_sec(m, 60.0)
        m
    end
    primal=solver()
    @variable(primal, pi[1:n, 1:n]>=0)
    @constraint(primal, [j=1:n], sum(pi[:, j])==weights[j])
    @constraint(primal, sum(distance .* pi)<=radius)
    @objective(primal, Max, sum(z[i]*pi[i, j] for i in 1:n, j in 1:n))
    optimize!(primal)
    primal_status(primal)==MOI.FEASIBLE_POINT || error("概率运输原问题没有可靠候选")
    dual=solver()
    @variable(dual, lambda>=0)
    @variable(dual, nu[1:n])
    @constraint(dual, [i=1:n, j=1:n], lambda*distance[i, j]+nu[j]>=z[i])
    @objective(dual, Min, lambda*radius+sum(weights .* nu))
    optimize!(dual)
    primal_status(dual)==MOI.FEASIBLE_POINT || error("概率运输对偶没有可靠候选")
    p=value.(pi)
    l=value(lambda)
    u=value.(nu)
    primal_residual=max(
        maximum(abs.(vec(sum(p; dims = 1))-weights)),
        max(0, sum(distance .* p)-radius),
        max(0, -minimum(p)),
    )
    dual_residual=max(0, -l, maximum(z[i]-l*distance[i, j]-u[j] for i in 1:n, j in 1:n))
    pv=sum(z[i]*p[i, j] for i in 1:n, j in 1:n)
    dv=l*radius+sum(weights .* u)
    Dict(
        "weights"=>weights,
        "z"=>z,
        "radius"=>radius,
        "probability"=>pv,
        "dual_value"=>dv,
        "distance"=>[collect(distance[i, :]) for i in 1:n],
        "lambda"=>l,
        "nu"=>u,
        "transport"=>[collect(p[i, :]) for i in 1:n],
        "worst_weights"=>vec(sum(p; dims = 2)),
        "primal_residual"=>primal_residual,
        "dual_residual"=>dual_residual,
        "duality_gap"=>abs(pv-dv),
        "primal_status"=>string(termination_status(primal)),
        "dual_status"=>string(termination_status(dual)),
    )
end

"""执行联合事件与有限支持运输的解析例，按显式新路径保存可重读的数值证据。"""
function audit_ch05()
    rows=Dict{String,Any}[]
    @testset "R5-Q05 complement and finite-support transport" begin
        @test joint_violation(falses(2, 3))==[0, 0, 0]
        @test joint_violation(trues(2, 3))==[1, 1, 1]
        single=Bool[true false; false true]
        @test joint_violation(single)==[1, 1]
        @test vec(all(single; dims = 1))==[false, false]
        # ε=.1时，原(5-75)的“全部违反”概率为0会接受；真正联合安全概率为0应拒绝。
        @test 0.0<=1-0.1
        @test !(1.0<=0.1)
        weights=[0.9, 0.1]
        dist=[0.0 1.0; 1.0 0.0]
        for z in ([0, 0], [0, 1], [1, 1]), radius in (0.0, 0.05, 0.2, 1.0)
            r=probability_oracle(weights, dist, z, radius)
            expected=z==[0, 0] ? 0.0 : z==[1, 1] ? 1.0 : min(1.0, 0.1+radius)
            @test r["probability"]≈expected atol=1e-7
            @test r["primal_residual"]<=1e-7
            @test r["dual_residual"]<=1e-7
            @test r["duality_gap"]<=1e-7
            @test sum(r["worst_weights"])≈1.0 atol=1e-8
            @test 1-r["probability"]≈1-expected atol=1e-7
            push!(rows, r)
        end
        weights3=[0.6, 0.3, 0.1]
        dist3=[abs(i-j)*1.0 for i in 1:3, j in 1:3]
        z3=[0, 1, 0]
        values=Float64[]
        for radius in (0.0, 0.05, 0.2, 0.6, 2.0)
            r=probability_oracle(weights3, dist3, z3, radius)
            @test r["probability"]≈min(1.0, 0.3+radius) atol=1e-7
            perm=[3, 1, 2]
            rr=probability_oracle(weights3[perm], dist3[perm, perm], z3[perm], radius)
            @test rr["probability"]≈r["probability"] atol=1e-7
            @test r["duality_gap"]<=1e-7
            push!(values, r["probability"])
            push!(rows, r)
        end
        @test all(diff(values) .>= -1e-8)
        @test_throws ErrorException probability_oracle([0.9, 0.9], dist, [0, 1], 0.1)
        @test_throws ErrorException probability_oracle(weights, dist, [0, 1], -0.1)
        @test_throws ErrorException probability_oracle(weights, dist, [0, 2], 0.1)
    end
    length(ARGS)<=1 || error("参数：[新证据文件路径]")
    if !isempty(ARGS)
        path=only(ARGS)
        ispath(path) && error("不覆盖概率审计证据")
        root=normpath(joinpath(@__DIR__, ".."))
        proof=Dict(
            "schema"=>"r5-q05-audit-v1",
            "origin"=>"synthetic_analytic",
            "scope"=>"Finite fixed support probability transport and event complement only; no market, thermal dispatch, Benders or continuous-support guarantee.",
            "source_pages"=>[92, 93, 94],
            "adopted_event"=>"sup P(any specified violation) <= epsilon",
            "script_sha256"=>bytes2hex(sha256(read(@__FILE__))),
            "project_sha256"=>bytes2hex(sha256(read(joinpath(root, "Project.toml")))),
            "manifest_sha256"=>bytes2hex(sha256(read(joinpath(root, "Manifest.toml")))),
            "julia"=>string(VERSION),
            "solver"=>"Clarabel",
            "solver_version"=>string(Base.pkgversion(Clarabel)),
            "source_sha256"=>TOML.parsefile(
                joinpath(root, "docs", "reading", "ch05", "probability-audit.toml"),
            )["source_sha256"],
            "tolerance"=>1e-7,
            "records"=>rows,
        )
        mkpath(dirname(path))
        open(path, "w") do io
            TOML.print(io, proof; sorted = true)
        end
    end
    println("Q05 event/complement and 17 primal-dual probability witnesses checked.")
end
audit_ch05()
