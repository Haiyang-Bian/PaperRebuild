# 临时诊断：不更改正式模型源码；把已验证固定域原值固定在自由域模型中，仅寻找辅助变量。
push!(LOAD_PATH,normpath(joinpath(@__DIR__,"..")))
using Gurobi,JuMP,TOML,SHA
include("../scripts/r8_tradeoff_study.jl")

function freeze_values!(assignments, rows, vars, packed, prefix)
    for (key,a) in vars
        v=PaperRebuild.r7_unpack(packed,key)
        size(a)==size(v)||error("shape mismatch $prefix/$key")
        for I in CartesianIndices(a)
            x,y=a[I],v[I]
            if x isa Real
                abs(x-y)<=1e-9||error("constant mismatch $prefix/$key")
                continue
            end
            if haskey(assignments,x)
                abs(assignments[x]-y)<=1e-12||error("duplicate assignment mismatch")
                continue
            end
            lower=has_lower_bound(x) ? max(0.0,lower_bound(x)-y) : 0.0
            upper=has_upper_bound(x) ? max(0.0,y-upper_bound(x)) : 0.0
            integer=is_binary(x)||is_integer(x) ? abs(y-round(y)) : 0.0
            bound=max(lower,upper,integer)
            bound<=1e-8||error("fixed witness exceeds target domain $prefix/$key")
            push!(rows,Dict("path"=>prefix*"/"*key*string(Tuple(I)),"value"=>y,"bound_residual"=>bound))
            assignments[x]=y
        end
    end
end

function run_probe()
    archive=joinpath(R8_ROOT,"results/summaries/r8-tradeoff-20260920-v1")
    dest=joinpath(R8_ROOT,"results/runs/r8-fixed-embedding-probe-20260920-v1")
    ispath(dest)&&error("do not overwrite probe")
    items,rule=r8_current_freeze(archive)
    selected=filter(x->x["control"]=="joint_continuous",items)
    mkpath(dest)
    write(joinpath(dest,"protocol.toml"),PaperRebuild.r7_text(Dict(
        "schema"=>"r8-fixed-embedding-probe-v1","origin"=>"synthetic",
        "ids"=>[x["id"] for x in selected],"budget_sec"=>60.0,
        "purpose"=>"Fix all saved physical states, decisions and flows; solve only auxiliary feasibility; not a new free-flow optimum or a rerun of the formal protocol.",
        "archive_sha256"=>r8_file_hash(joinpath(archive,"report-hashes.toml")),
        "script_sha256"=>r8_file_hash(@__FILE__),"science"=>PaperRebuild.r8_science_hashes())) )
    cp(@__FILE__,joinpath(dest,"probe-source.jl"))
    for item in selected
        parent=only(filter(x->x["family"]==item["family"]&&x["control"]=="fixed"&&
            x["mode"]==item["mode"]&&x["solver"]==item["solver"]&&
            x["resource"]==item["resource"]&&x["limit_MWh"]==item["limit_MWh"],items))
        parent["case_sha256"]==item["case_sha256"]||error("case differs")
        p=TOML.parsefile(joinpath(archive,"records",parent["id"],"result.toml"))["primary"]
        p["validation"]["model_pass"]||error("invalid parent")
        c=R7PlanningCase(R7NormalCase(item["normal"]),item["planning"])
        started=time(); deadline=started+60
        r=Dict{String,Any}("id"=>item["id"],"parent_id"=>parent["id"],"parent_stage_run_id"=>p["run_id"],"status"=>"not_solved")
        try
            b=build_r8_model(c,item["flow"],item["spec"];optimizer=r8_study_optimizer("Gurobi"),deadline)
            assignments=Dict{VariableRef,Float64}();rows=Any[]
            freeze_values!(assignments,rows,b.normal_variables,p["normal"]["values"],"normal")
            freeze_values!(assignments,rows,b.normal_flow,p["normal"]["flow_values"],"normal_flow")
            for (id,v) in b.chp_variables
                freeze_values!(assignments,rows,v,p["normal"]["chp_values"][id],"CHP/"*id)
            end
            for w in b.recovery
                old=only(filter(z->z["event"]==w.pair.event&&z["fault"]==w.pair.fault,p["witnesses"]))
                key=PaperRebuild.r7_planning_pair_key(w.pair)
                for (v,field) in ((w.variables,"values"),(w.thermal_variables,"thermal_values"),(w.boundary_parameters,"boundary_values"))
                    freeze_values!(assignments,rows,v,old[field],key*"/"*field)
                end
            end
            for (j,v) in enumerate(b.eta)
                assignments[v]=p["eta_MWh"][j]
            end
            for (v,x) in assignments
                fix(v,x;force=true)
            end
            r["fixed_values"]=rows
            r["fixed_variable_count"]=length(assignments)
            r["model_variable_count"]=num_variables(b.model)
            r["build_sec"]=time()-started
            @objective(b.model,Min,0.0)
            set_silent(b.model)
            set_time_limit_sec(b.model,max(0.0,deadline-time()))
            optimize!(b.model)
            r["status"]=string(termination_status(b.model))
            r["primal_status"]=string(primal_status(b.model))
            if has_values(b.model) && primal_status(b.model) in (MOI.FEASIBLE_POINT,MOI.NEARLY_FEASIBLE_POINT)
                snap=PaperRebuild.r8_snapshot(b,c,item["flow"],item["spec"],"probe")
                candidate=deepcopy(p)
                candidate["normal"],candidate["witnesses"],candidate["eta_MWh"]=snap.normal,snap.witnesses,snap.eta
                candidate["solver_objective"]=p["solver_objective"]
                delete!(candidate,"objective_lower_bound")
                r["reconstructed_values"]=candidate
                r["independent_validation"]=PaperRebuild.r8_validate_stage(c,item["flow"],item["spec"],candidate)
                r["max_preservation_error"]=maximum(abs(value(v)-x) for (v,x) in assignments;init=0.0)
                violations=primal_feasibility_report(b.model;atol=0)
                r["maximum_solver_model_violation"]=maximum(values(violations);init=0.0)
                r["model_violations"]=[Dict("constraint"=>string(con),"violation"=>v) for (con,v) in violations]
            end
        catch err
            r["status"]="probe_error"
            r["error"]=sprint(showerror,err)
        end
        r["elapsed_sec"]=time()-started
        write(joinpath(dest,item["id"]*".toml"),PaperRebuild.r7_text(r))
        println(item["id"]," ",r["status"]," pass=",get(get(r,"independent_validation",Dict()),"model_pass",false)," error=",get(r,"error","none"))
        flush(stdout)
    end
end
run_probe()
