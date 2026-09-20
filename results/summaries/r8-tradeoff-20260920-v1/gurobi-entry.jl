# 求解器环境只含优化依赖；根环境的锁定CSV仅供报告编排，不新增或替换优化包。
push!(LOAD_PATH, normpath(joinpath(@__DIR__, "..")))
using Gurobi
include("r8_tradeoff_study.jl")
length(ARGS)==1 || error("usage: run_r8_gurobi.jl FROZEN_BATCH")
dir=abspath(only(ARGS))
note=joinpath(dir,"gurobi-launch.toml")
ispath(note)&&error("不覆盖R8商用启动记录")
cp(@__FILE__,joinpath(dir,"gurobi-entry.jl"))
write(note,PaperRebuild.r7_text(Dict(
    "schema"=>"r8-environment-launch-v1",
    "reason"=>"Initial direct launch stopped before optimization: CSV is not a direct dependency of tools/solvers. Root project is appended to LOAD_PATH; all frozen science and inputs remain unchanged.",
    "command"=>"julia +1.12.6 --startup-file=no --project=tools/solvers scripts/run_r8_gurobi.jl FROZEN_BATCH",
    "entry_sha256"=>r8_file_hash(@__FILE__),
    "root_project_sha256"=>r8_file_hash(joinpath(R8_ROOT,"Project.toml")),
    "root_manifest_sha256"=>r8_file_hash(joinpath(R8_ROOT,"Manifest.toml")),
    "solver_project_sha256"=>r8_file_hash(joinpath(R8_ROOT,"tools/solvers/Project.toml")),
    "solver_manifest_sha256"=>r8_file_hash(joinpath(R8_ROOT,"tools/solvers/Manifest.toml")),
)))
r8_study_run(dir,"Gurobi")
