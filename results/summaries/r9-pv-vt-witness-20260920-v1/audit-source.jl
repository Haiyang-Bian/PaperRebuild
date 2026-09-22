# 诊断同一模型的状态矛盾；不改变正式输入或覆盖已有运行。
push!(LOAD_PATH,normpath(joinpath(@__DIR__,"..")))
using JuMP, Gurobi, TOML, CSV, SHA, Dates
include("r9_pv_study.jl")
length(ARGS) in (3,4) || error("usage: audit_r9_solver.jl BATCH CF_CT|CF_VT NEW_AUDIT [witness-only]")
length(ARGS)==3 || ARGS[4]=="witness-only" || error("未知审计选项")
batch,mode,out=abspath(ARGS[1]),Symbol(ARGS[2]),abspath(ARGS[3])
ispath(out) && error("不覆盖诊断")
f=R9PVStudy.frozen(batch)
r=TOML.parsefile(joinpath(batch,"runs",lowercase(string(mode))*"_clarabel_socp","result.toml"))
stage=get(r,"reconstructed",r["stage"])
start=time()
b=Base.invokelatest(()->getfield(f.mod,:build_r9_pv_model)(f.c;mode))
point=Dict{VariableRef,Float64}()
for (key,arr) in b.variables
    vars=Array(arr)
    x=stage["values"][key]
    vals=ndims(vars)==1 ? Float64.(x) : permutedims(hcat(x...))
    size(vars)==size(vals) || error("变量形状不一致：$key")
    for i in eachindex(vars)
        point[vars[i]]=vals[i]
    end
end
# 旧R2记录没有保存匿名乘积辅助量。仅由一个未知量的线性等式重构，保持所有保存控制量不变。
auxiliary=NamedTuple[]
for _ in 1:3
    before=length(point)
    for cr in all_constraints(b.model,AffExpr,MOI.EqualTo{Float64})
        obj=constraint_object(cr)
        unknown=[(coef,x) for (coef,x) in linear_terms(obj.func) if !haskey(point,x) && coef!=0]
        length(unknown)==1 || continue
        coef,x=only(unknown)
        known=constant(obj.func)+sum(a*point[y] for (a,y) in linear_terms(obj.func) if haskey(point,y);init=0.0)
        point[x]=(obj.set.value-known)/coef
        push!(auxiliary,(variable=string(x),value=point[x],equation=string(cr)))
    end
    length(point)==before && break
end
Set(keys(point))==Set(all_variables(b.model)) || error("仍有未重构变量")
distances=primal_feasibility_report(b.model,point;atol=0.0)
rows=[(constraint=string(cr),distance=v) for (cr,v) in distances]
sort!(rows;by=x->(-x.distance,x.constraint))
mkpath(out)
CSV.write(joinpath(out,"all-constraint-distances.csv"),rows)
CSV.write(joinpath(out,"auxiliary-reconstruction.csv"),auxiliary)
cp(@__FILE__,joinpath(out,"audit-source.jl"))
meta=Dict{String,Any}("schema"=>"r9-solver-audit-v1","mode"=>string(mode),"input_sha256"=>f.c.sha256,
    "parent_manifest_sha256"=>R9PVStudy.hashfile(joinpath(batch,"manifest.toml")),
    "witness_result_sha256"=>R9PVStudy.hashfile(joinpath(batch,"runs",lowercase(string(mode))*"_clarabel_socp","result.toml")),
    "variable_count"=>length(point),"constraint_count"=>num_constraints(b.model;count_variable_in_set_constraints=true),
    "reconstructed_auxiliary_count"=>length(auxiliary),
    "max_raw_constraint_distance"=>maximum(values(distances);init=0.0))
if length(ARGS)==3
set_optimizer(b.model,Gurobi.Optimizer)
for (key,value) in ("Threads"=>1,"Seed"=>0,"NonConvex"=>2,"FeasibilityTol"=>1e-9,"OptimalityTol"=>1e-9,"BarConvTol"=>1e-10,"MIPGap"=>1e-6,"QCPDual"=>1)
    set_optimizer_attribute(b.model,key,value)
end
set_time_limit_sec(b.model,max(0.01,60-(time()-start)))
optimize!(b.model)
meta["termination"]=string(termination_status(b.model))
if termination_status(b.model)==MOI.INFEASIBLE && time()-start<59
    try
        set_time_limit_sec(b.model,max(0.01,60-(time()-start)))
        compute_conflict!(b.model)
        meta["conflict_status"]=string(MOI.get(b.model,MOI.ConflictStatus()))
        conflicts=String[]
        for cr in all_constraints(b.model;include_variable_in_set_constraints=true)
            status=MOI.get(b.model,MOI.ConstraintConflictStatus(),cr)
            status==MOI.NOT_IN_CONFLICT || push!(conflicts,string(status)*": "*string(cr))
        end
        write(joinpath(out,"conflict.txt"),join(conflicts,"\n")*"\n")
    catch err
        meta["conflict_error"]=sprint(showerror,err)
    end
end
end
meta["elapsed_sec"]=time()-start
meta["files"]=Dict(name=>R9PVStudy.hashfile(joinpath(out,name)) for name in readdir(out))
write(joinpath(out,"audit.toml"),R9PVStudy.textfile(meta))
println(meta)
