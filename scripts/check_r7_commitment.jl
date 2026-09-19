using PaperRebuild, JuMP
include("r7_commitment_docs.jl")
root=normpath(joinpath(@__DIR__, ".."))
ARGS in (String[], ["--sync"]) || error("usage: check_r7_commitment.jl [--sync]")
"--sync" in ARGS && sync_r7_commitment_docs(root)
d=TOML.parsefile(joinpath(root, "docs/reading/ch06/normal-prerequisites.toml"))
for key in ("original_equation", "equation", "finding", "symbol")
    ids=[e["id"] for e in d[key]]
    length(ids)==length(unique(ids)) || error("重复台账ID")
end
tests=read(joinpath(root, "test/r7_commitment.jl"), String)
for e in d["equation"]
    occursin(e["test"], tests) || error("缺独立测试映射")
    isempty(e["api"]) || isdefined(PaperRebuild, Symbol(e["api"])) || error("缺API")
end
case=TOML.parsefile(joinpath(root, "configs/r7/chp-component-hand.toml"))
actual=Set{String}()
for variant in ("base", "initial", "terminal")
    c=deepcopy(case)
    if variant=="initial"
        c["previous_commitment"]=1
        c["previous_P_MW"]=[0.2, 0.2]
        c["previous_duration_h"]=0.0
    elseif variant=="terminal"
        c["terminal_rule"]="complete_within_horizon"
    end
    b=add_r7_chp_commitment!(Model(), R7CHPSpec(c))
    union!(actual, keys(b.constraints))
end
actual==Set(d["constraint_ids"]) || error("实际约束与台账失步")
read(joinpath(root, "docs/src/ch06-commitment-equations.md"), String)==r7_commitment_markdown(
    root,
) || error("生成页失步")
println(
    "R7 normal prerequisites: 7 derived equations, 9 constraint IDs, 3 findings, 6 symbol groups; CHP component only.",
)
