# 一次冻结批次，失败也封存；不根据求解结果调整配置/容差。
include("r4_setup.jl")
root=normpath(joinpath(@__DIR__, ".."))
study=TOML.parsefile(joinpath(root, "configs", "r4", "study.toml"))
batch=isempty(ARGS) ? "r4-"*Dates.format(now(), "yyyymmdd-HHMMSS") : only(ARGS)
occursin(r"^[A-Za-z0-9_-]+$", batch) || error("非法批次ID")
dest=joinpath(root, "results", "runs", "r4", batch)
ispath(dest) && error("不覆盖已有批次")
mkpath(dest)
manifest=Dict{String,Any}(
    "batch"=>batch,
    "study_sha256"=>bytes2hex(sha256(read(joinpath(root, "configs", "r4", "study.toml")))),
    "origin"=>"synthetic",
    "runs"=>Dict{String,Any}[],
)
opt=r4_optimizer(:gurobi)
for entry in study["case"], variant in study["variants"]
    c=load_r4_case(joinpath(root, "configs", "r4", entry["name"]*".toml"))
    c.sha256==entry["sha256"] || error("冻结输入哈希改变")
    spec=R4Spec(
        operation = startswith(variant, "independent") ? :independent : :central,
        electric = endswith(variant, "exact") ? :exact : :socp,
    )
    id=entry["name"]*"--"*variant
    r=solve_r4_case(c; spec, optimizer = opt, budget_sec = study["budget_sec"])
    path=save_r4_run(c, r; directory = dest, run_id = id)
    read_r4_run(path)
    push!(manifest["runs"], Dict("case"=>entry["name"], "variant"=>variant, "directory"=>id))
    write(joinpath(dest, "study.toml"), PaperRebuild.r4_text(manifest))
    println(
        id,
        " | ",
        r["status"],
        " | A1=",
        r["validation"]["model_pass"],
        " | cost=",
        get(r, "operating_cost", "none"),
    )
    flush(stdout)
end
# 开放求解器独立同模型对照，不是Gurobi的初值来源。
c=load_r4_case(joinpath(root, "configs", "r4", "base.toml"))
r=solve_r4_case(c; optimizer = r4_optimizer(:clarabel), enumerate_battery = true, budget_sec = 60)
path=save_r4_run(c, r; directory = dest, run_id = "base--clarabel_enumeration")
read_r4_run(path)
push!(
    manifest["runs"],
    Dict(
        "case"=>"base",
        "variant"=>"clarabel_enumeration",
        "directory"=>"base--clarabel_enumeration",
    ),
)
write(joinpath(dest, "study.toml"), PaperRebuild.r4_text(manifest))
println("Complete: ", joinpath(dest, "study.toml"))
