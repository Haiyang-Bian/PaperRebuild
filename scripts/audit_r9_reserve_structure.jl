# 只构建冻结模型，记录真实规模与支持几何；不设置求解器、不求解。
using TOML, SHA, JuMP, CSV
include("r9_reserve_study.jl")
include("r9_reserve_support.jl")
length(ARGS)==2 || error("usage: audit_r9_reserve_structure.jl STUDY NEW_OUTPUT")
study, out=abspath.(ARGS)
ispath(out) && error("Preserve previous audit")
started=time_ns()/1e9
b=R9ReserveStudy.check(study)
e=only(e for e in b.manifest["methods"] if e["id"]=="full100-3a")
c=R9ReserveStudy.call(
    b.lib,
    :r9_reserve_risk_case,
    b.template,
    b.dataset.sets["train"],
    b.dataset.representatives,
    b.spec,
    "3A",
)
start=time_ns()/1e9
model=R9ReserveStudy.call(b.lib, :build_r5_risk, c; pattern = zeros(Int, 100))
buildsec=time_ns()/1e9-start
rows=[
    (function_type = string(F), set_type = string(S), count = num_constraints(model.model, F, S))
    for (F, S) in list_of_constraint_types(model.model)
]
sort!(rows; by = x->(x.function_type, x.set_type))
mkpath(out)
CSV.write(joinpath(out, "constraint-types.csv"), rows; newline = '\n')
data=Dict(
    "schema"=>"r9-reserve-structure-audit-v1",
    "origin"=>"synthetic",
    "study_manifest_sha256"=>R9ReserveStudy.hashfile(joinpath(study, "manifest.toml")),
    "case_sha256"=>c.sha256,
    "variables"=>num_variables(model.model),
    "constraints_including_variable_sets"=>sum(x.count for x in rows),
    "binary_variables"=>count(is_binary, all_variables(model.model)),
    "model_type"=>model.model_type,
    "optimizer_attached"=>false,
    "build_sec"=>buildsec,
    "elapsed_sec"=>time_ns()/1e9-started,
)
R9ReserveStudy.toml(joinpath(out, "audit.toml"), data)
support=NamedTuple[]
original=c.data["commitment"]["scenarios"]
p=[s["probability"] for s in original]
D=R9ReserveStudy.call(b.lib, :r5_market_array, c.data["ambiguity"]["distance"])
for scheme in ("3A", "3B", "3C"), i in eachindex(p)
    rho=scheme=="3A" ? maximum(D) : scheme=="3B" ? 0.0 : b.spec.data["radius"]
    epsilon=scheme=="3A" ? 0.0 : 0.05
    bound=R9ReserveSupport.single_event_bound(p, D, rho, i)
    push!(
        support,
        (
            scheme,
            scenario = original[i]["id"],
            probability = p[i],
            worst_single_event = bound,
            epsilon,
            individually_allowed = bound<=epsilon+1e-8,
        ),
    )
end
CSV.write(joinpath(out, "single-event-support.csv"), support; newline = '\n')
cp(@__FILE__, joinpath(out, "audit-source.jl"))
R9ReserveStudy.toml(
    joinpath(out, "files.toml"),
    Dict("files"=>Dict(f=>R9ReserveStudy.hashfile(joinpath(out, f)) for f in readdir(out))),
)
println(
    "Actual model variables=",
    data["variables"],
    " constraints=",
    data["constraints_including_variable_sets"],
    " build_seconds=",
    buildsec,
)
for scheme in ("3A", "3B", "3C")
    r=filter(x->x.scheme==scheme, support)
    println(
        scheme,
        " individually allowed=",
        count(x->x.individually_allowed, r),
        " range=",
        extrema(x.worst_single_event for x in r),
    )
end
