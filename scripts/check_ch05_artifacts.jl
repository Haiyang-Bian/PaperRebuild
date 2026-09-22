using TOML, SHA
include("check_ch05_probability.jl")
# 独立重读第5章概率/条件割冻结证据，核验副本、生产脚本及代数；不重新求解。
root=normpath(joinpath(@__DIR__, ".."))
for (folder, script) in
    (("ch05-probability", "audit_ch05_probability.jl"), ("ch05-cuts", "audit_ch05_cuts.jl"))
    source=joinpath(root, "results", "summaries", folder, "proof.toml")
    target=joinpath(root, "docs", "src", "assets", folder, "proof.toml")
    read(source)==read(target) || error("文档证据副本变化")
    d=TOML.parsefile(source)
    d["script_sha256"]==bytes2hex(sha256(read(joinpath(root, "scripts", script)))) ||
        error("证据生产脚本变化")
    occursin(r"(?i)[A-Z]:[\\/]|/Users/|/home/", read(source, String)) && error("证据含本机路径")
    if folder=="ch05-cuts"
        length(d["records"])==10 && d["lower_bound"]==-3.0 || error("反例清单变化")
        for r in d["records"]
            x, z=r["x"], r["z"]
            q0, q1=1-x, -2-x
            r["recourse"]==(z==0 ? q0 : q1) &&
            r["literal"]==max(q0*(1-z), q1*z) &&
            r["checked"]==max(-3+(q0+3)*(1-z), -3+(q1+3)*z) || error("条件割见证独立回算失败")
        end
    end
end
proof_path=joinpath(root, "results", "summaries", "ch05-probability", "proof.toml")
check_ch05_probability(proof_path)
audit_path=joinpath(root, "results", "summaries", "ch05-probability", "a1-audit.toml")
audit_copy=joinpath(root, "docs", "src", "assets", "ch05-probability", "a1-audit.toml")
read(audit_path)==read(audit_copy) || error("A1补证的文档副本变化")
occursin(r"(?i)[A-Z]:[\\/]|/Users/|/home/", read(audit_path, String)) && error("A1补证含本机路径")
audit=TOML.parsefile(audit_path)
audit["schema"]=="r5-q05-a1-audit-v1" && audit["origin"]=="synthetic_analytic" ||
    error("A1补证身份错误")
audit["original_algebra_tolerance"]==1e-7 && audit["A1_probability_tolerance"]==1e-8 ||
    error("A1补证门槛变化")
for (key, rel) in (
    ("proof_sha256", "results/summaries/ch05-probability/proof.toml"),
    ("script_sha256", "scripts/audit_ch05_probability_a1.jl"),
    ("checker_sha256", "scripts/check_ch05_probability.jl"),
)
    audit[key]==bytes2hex(sha256(read(joinpath(root, rel)))) || error("A1补证来源变化：$rel")
end
proof=TOML.parsefile(proof_path)
length(audit["records"])==length(proof["records"])==17 || error("A1补证见证缺失")
residuals=Float64[]
for (i, r) in enumerate(proof["records"])
    transport=reduce(vcat, permutedims.(r["transport"]))
    distance=reduce(vcat, permutedims.(r["distance"]))
    worst=vec(sum(transport; dims = 2))
    residual=max(
        0.0,
        -minimum(transport),
        maximum(abs.(vec(sum(transport; dims = 1))-r["weights"])),
        sum(transport .* distance)-r["radius"],
        abs(sum(worst)-1),
        -minimum(worst),
    )
    saved=audit["records"][i]
    saved["witness"]==i && saved["tolerance"]==1e-8 && saved["pass"]===true ||
        error("A1见证索引或判定变化")
    residual<=1e-8 && abs(residual-saved["probability_transport_residual"])<=1e-15 ||
        error("A1见证独立回算失败")
    push!(residuals, residual)
end
abs(maximum(residuals)-audit["max_residual"])<=1e-15 || error("A1最大残差摘要错误")
println(
    "Two original proofs and the separate A1 supplement: copies, hashes and independent replay passed.",
)
