# 所有输入/方式先于求解冻结；AG0仍冻结局部控制，不用集中解救援。
include("r4_setup.jl")
root=normpath(joinpath(@__DIR__, ".."))
frozen=joinpath(root, "configs", "r4", "baseline", "study.toml")
study=TOML.parsefile(frozen)
batch=isempty(ARGS) ? "r4-baseline-"*Dates.format(now(), "yyyymmdd-HHMMSS") : only(ARGS)
occursin(r"^[A-Za-z0-9_-]+$", batch) || error("非法批次ID")
dest=joinpath(root, "results", "runs", "r4", batch)
ispath(dest) && error("不覆盖已有批次")
mkpath(dest)
manifest=Dict{String,Any}(
    "batch"=>batch,
    "origin"=>"synthetic",
    "study_sha256"=>bytes2hex(sha256(read(frozen))),
    "runs"=>Dict{String,Any}[],
)
opt=r4_optimizer(:gurobi)
for entry in study["case"], variant in study["variants"]
    c=load_r4_case(joinpath(root, "configs", "r4", "baseline", entry["name"]*".toml"))
    c.sha256==entry["sha256"] || error("冻结输入改变")
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
        " | original A1=",
        r["validation"]["electric_original_pass"],
        " | cost=",
        get(r, "operating_cost", "none"),
    )
    flush(stdout)
end
c=load_r4_case(joinpath(root, "configs", "r4", "baseline", "import_flexible.toml"))
r=solve_r4_case(
    c;
    optimizer = r4_optimizer(:clarabel),
    enumerate_battery = true,
    budget_sec = study["clarabel_budget_sec"],
)
id="import_flexible--clarabel_enumeration"
path=save_r4_run(c, r; directory = dest, run_id = id)
read_r4_run(path)
push!(
    manifest["runs"],
    Dict("case"=>"import_flexible", "variant"=>"clarabel_enumeration", "directory"=>id),
)
write(joinpath(dest, "study.toml"), PaperRebuild.r4_text(manifest))
println("Saved 13 R4 baseline records: ", joinpath(dest, "study.toml"))
