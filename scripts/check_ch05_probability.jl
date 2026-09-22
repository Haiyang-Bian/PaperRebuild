using TOML, SHA

"""
从冻结概率审计记录独立回算运输、对偶可行性和解析最优值，不重新调用求解器。
证据限于有限支持联合违约模型，不能认证尚未实现的调度或样本外风险。
"""
function check_ch05_probability(path)
    root=normpath(joinpath(@__DIR__, ".."))
    d=TOML.parsefile(path)
    d["schema"]=="r5-q05-audit-v1" && d["origin"]=="synthetic_analytic" || error("概率证据身份错误")
    for (key, rel) in (
        ("script_sha256", "scripts/audit_ch05_probability.jl"),
        ("project_sha256", "Project.toml"),
        ("manifest_sha256", "Manifest.toml"),
    )
        bytes2hex(sha256(read(joinpath(root, rel))))==d[key] || error("概率证据来源变化：$rel")
    end
    ledger=TOML.parsefile(joinpath(root, "docs", "reading", "ch05", "probability-audit.toml"))
    d["source_sha256"]==ledger["source_sha256"] || error("论文版本变化")
    d["tolerance"]==1e-7 || error("验收门槛变化")
    length(d["records"])==17 || error("见证缺失")
    for r in d["records"]
        p=reduce(vcat, permutedims.(r["transport"]))
        distance=reduce(vcat, permutedims.(r["distance"]))
        w, z, u=r["weights"], r["z"], r["nu"]
        λ, ρ=r["lambda"], r["radius"]
        n=length(w)
        size(p)==size(distance)==(n, n) && length(z)==length(u)==n || error("维度变化")
        all(isfinite, p) &&
        all(isfinite, distance) &&
        all(isfinite, w) &&
        all(isfinite, u) &&
        isfinite(λ) &&
        isfinite(ρ) || error("非有限数值")
        all(x->x in (0, 1), z) &&
        minimum(w)>=0 &&
        abs(sum(w)-1)<=1e-12 &&
        minimum(distance)>=0 &&
        all(distance[i, i]==0 for i in 1:n) &&
        ρ>=0 || error("输入不满足原问题定义")
        primal_residual=max(
            0,
            -minimum(p),
            maximum(abs.(vec(sum(p; dims = 1))-w)),
            sum(p .* distance)-ρ,
        )
        # 原97项解析审计的统一比较带宽1e-7不替代A1概率门槛1e-8。
        worst=vec(sum(p; dims = 2))
        maximum((primal_residual, abs(sum(worst)-1), max(0.0, -minimum(worst))))<=1e-8 ||
            error("A1概率/运输守恒验收失败")
        dual_residual=max(0, -λ, maximum(z[i]-λ*distance[i, j]-u[j] for i in 1:n, j in 1:n))
        primal=sum(z[i]*p[i, j] for i in 1:n, j in 1:n)
        dual=λ*ρ+sum(w .* u)
        # 本次冻结的两点和三点解析例，所有安全点到唯一失败点的最小距离都是1。
        expected=all(z .== 0) ? 0.0 : all(z .== 1) ? 1.0 : min(1.0, sum(w .* z)+ρ)
        maximum((primal_residual, dual_residual, abs(primal-dual), abs(primal-expected)))<=1e-7 ||
            error("原对偶或解析验收失败")
        maximum(
            abs.(
                (primal, dual, primal_residual, dual_residual, abs(primal-dual)) .- (
                    r["probability"],
                    r["dual_value"],
                    r["primal_residual"],
                    r["dual_residual"],
                    r["duality_gap"],
                ),
            ),
        )<=1e-12 || error("保存摘要与独立回算不一致")
        maximum(abs.(vec(sum(p; dims = 2))-r["worst_weights"]))<=1e-12 ||
            error("最坏概率不是运输行和")
    end
    println("Q05: 17 frozen primal-dual witnesses independently checked; no optimization.")
    nothing
end

if abspath(PROGRAM_FILE)==@__FILE__
    length(ARGS)<=1 || error("参数：[冻结proof.toml]")
    check_ch05_probability(
        isempty(ARGS) ?
        joinpath(@__DIR__, "..", "results", "summaries", "ch05-probability", "proof.toml") :
        only(ARGS),
    )
end
