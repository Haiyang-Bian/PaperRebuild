# 一项预先声明的数值诊断因素：只关闭Presolve，方程、边界、A1和求解容差均不变。
push!(LOAD_PATH,normpath(joinpath(@__DIR__,"..")))
using Gurobi, JuMP, TOML, CSV, Dates
include("r9_pv_study.jl")
length(ARGS)==2 || error("usage: r9_presolve_check.jl BATCH NEW_DIAGNOSTIC")
batch,out=abspath.(ARGS)
ispath(out) && error("不覆盖诊断")
f=R9PVStudy.frozen(batch)
mkpath(out)
cp(@__FILE__,joinpath(out,"study-source.jl"))
entries=[Dict("mode"=>mode,"physical"=>physical,"budget_sec"=>600.0) for mode in ("CF_CT","CF_VT"), physical in (false,true)]
write(joinpath(out,"manifest.toml"),R9PVStudy.textfile(Dict("schema"=>"r9-presolve-diagnostic-v1",
    "hypothesis"=>"Resolve solver-status contradiction by changing only Presolve; do not rewrite previous INFEASIBLE runs",
    "parameter"=>Dict("Presolve"=>0),"created_utc"=>string(now(UTC)),"entries"=>vec(entries),
    "parent_manifest_sha256"=>R9PVStudy.hashfile(joinpath(batch,"manifest.toml")),"input_sha256"=>f.c.sha256,
    "study_source_sha256"=>R9PVStudy.hashfile(joinpath(out,"study-source.jl")))))
rows=NamedTuple[]
for entry in entries
    mode,physical=Symbol(entry["mode"]),entry["physical"]
    id=lowercase(string(mode))*(physical ? "_original" : "_socp")
    r=Base.invokelatest(()->getfield(f.mod,:solve_r9_pv_case)(f.c;mode,physical,
        optimizer=optimizer_with_attributes(Gurobi.Optimizer,"Presolve"=>0),budget_sec=600.0))
    r["solver_attributes"]=Dict("Presolve"=>0)
    write(joinpath(out,id*".toml"),R9PVStudy.textfile(r))
    v=Base.invokelatest(()->getfield(f.mod,:validate_r9_pv_solution)(f.c,r))
    s=r["stage"]
    push!(rows,(id,mode=string(mode),physical_model=physical,status=r["status"],model_pass=v.model_pass,physical_pass=v.physical_pass,
        terminal_pass=v.terminal_pass,cost_CNY=get(s,"operating_cost",missing),bound_CNY=get(s,"solver_bound",missing),
        gap=get(s,"solver_relative_gap",missing),elapsed_sec=r["elapsed_sec"],wall_budget_pass=r["wall_budget_pass"]))
    CSV.write(joinpath(out,"summary.csv"),rows)
    println(id,": ",r["status"],"; ",r["validation"],"; cost=",get(s,"operating_cost","missing"))
    flush(stdout)
end
write(joinpath(out,"evidence.toml"),R9PVStudy.textfile(Dict("files"=>Dict(p=>R9PVStudy.hashfile(joinpath(out,p)) for p in readdir(out)))))
