using TOML, SHA
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
println(
    "Two frozen proof files: matching public copies, producer hashes and conditional-cut replay checked.",
)
