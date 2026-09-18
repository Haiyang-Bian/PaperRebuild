# R4第二批：先冻结偏好/制度差异，再计算。旧配置和负结果不改写。
using PaperRebuild, TOML, SHA
root=normpath(joinpath(@__DIR__, ".."))
parent=load_r4_case(joinpath(root, "configs", "r4", "base.toml"))
function freeze_baseline(path, d)
    text=PaperRebuild.r4_text(d)
    isfile(path) && read(path, String)!=text && error("拒绝覆盖冻结配置: "*path)
    mkpath(dirname(path))
    isfile(path) || write(path, text)
    return bytes2hex(sha256(text))
end
entries=Dict{String,Any}[]
for admission in ("unrestricted", "import_only_v1"), flexible in (true, false)
    d=deepcopy(parent.data)
    name=(admission=="unrestricted" ? "open" : "import")*(flexible ? "_flexible" : "_fixed")
    d["name"]=name
    d["parent_sha256"]=parent.sha256
    d["description"]="R4第二批合成对照；偏好独立于可调范围；仅购能制度为项目对照，非作者设定。"
    d["preference_model"]="explicit_reference_v1"
    d["admission_policy"]=admission
    for a in d["actors"]
        for carrier in ("P", "H")
            a[carrier*"_preferred"]=(1+a["flex"]) .* a[carrier*"_load"]
        end
        flexible || (a["flex"]=0.0)
    end
    R4Case(d)
    hash=freeze_baseline(joinpath(root, "configs", "r4", "baseline", name*".toml"), d)
    push!(entries, Dict("name"=>name, "sha256"=>hash))
end
freeze_baseline(
    joinpath(root, "configs", "r4", "baseline", "study.toml"),
    Dict(
        "schema"=>"r4-baseline-study-v1",
        "origin"=>"synthetic",
        "case"=>entries,
        "parent_sha256"=>parent.sha256,
        "variants"=>["independent_exact", "central_socp", "central_exact"],
        "budget_sec"=>600,
        "clarabel_budget_sec"=>60,
        "control"=>"同偏好/设备/网络/价格；制度与灵活范围分别变化。AG0冻结后仍须网络校核。",
        "not_claimed"=>["author_data_match", "complete_thermal_physics", "bargaining"],
    ),
)
println("R4 baseline: four input pairs frozen before optimization.")
