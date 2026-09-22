using TOML,SHA,CSV

function r7_evidence_hashes(dir)
    Dict(replace(relpath(joinpath(path,file),dir),'\\'=>'/')=>bytes2hex(sha256(read(joinpath(path,file)))) for (path,_,files) in walkdir(dir) for file in files if joinpath(path,file)!=joinpath(dir,"evidence-files.toml"))
end

function r7_evidence_check_files(dir,hashes)
    for p in keys(hashes)
        !isabspath(p)&&!occursin(':',p)&&!occursin('\\',p)&&all(x->!(x in ("",".","..")),split(p,'/')) || error("证据路径非法")
    end
    hashes==r7_evidence_hashes(dir) || error("证据文件缺失、增加或被改变")
end

function r7_normal_evidence_values(dir)
    dir=abspath(dir)
    # 独立模块加载原存档源码；当前PaperRebuild升级不能改变旧正常/恢复判定。
    holder=Module(gensym(:R7Evidence))
    Base.include(holder,joinpath(dir,"normal","code","replay.jl"))
    api=Base.invokelatest(getfield,holder,:FrozenR7Normal)
    call(f,args...;kw...)=Base.invokelatest(Base.invokelatest(getfield,api,f),args...;kw...)
    normal=call(:read_r7_normal,joinpath(dir,"normal"))
    ncase,nr=normal.case,normal.result
    eventdir=joinpath(dir,"event")
    em=TOML.parsefile(joinpath(eventdir,"event-files.toml"))["files"]
    actual=Dict(replace(relpath(joinpath(path,file),eventdir),'\\'=>'/')=>bytes2hex(sha256(read(joinpath(path,file)))) for (path,_,files) in walkdir(eventdir) for file in files if joinpath(path,file)!=joinpath(eventdir,"event-files.toml"))
    em==actual || error("事件原文件被改变")
    ec=call(:load_r7_recovery_case,joinpath(eventdir,"case.toml"));handoff=TOML.parsefile(joinpath(eventdir,"handoff.toml"))
    rebuild=call(:r7_normal_event,ncase,nr;event_start=ec.data["event_start"],periods=ec.data["periods"],renewable_factor=ec.data["renewable_factor"],loss_limit_MWh=ec.data["loss_limit_MWh"])
    rebuild.case.sha256==ec.sha256 && isequal(rebuild.evidence,handoff) || error("事件状态不来自原正常轨迹")
    ev=TOML.parsefile(joinpath(eventdir,"event.toml"))
    ev["schema"]=="r7-normal-event-runs-v1" && ev["parent_case_sha256"]==ncase.sha256 && ev["parent_run_id"]==nr["run_id"] || error("事件父身份错误")
    [r["fault"] for r in ev["records"]]==call(:r7_faults,ec) || error("冻结故障记录覆盖错误")
    runs=Any[]
    for record in ev["records"]
        occursin(r"^fault-[0-9]+$",record["directory"]) || error("恢复目录错误")
        x=call(:read_r7_recovery,joinpath(eventdir,record["directory"]))
        x.case.sha256==ec.sha256 && x.result["run_id"]==record["run_id"] && x.result["fault"]==record["fault"] &&
            x.result["status"]==record["status"] && x.validation["model_pass"]==record["model_pass"] &&
            x.result["parent_normal_run_id"]==nr["run_id"] && x.result["parent_normal_result_sha256"]==handoff["parent_result_sha256"] || error("恢复原值/来源不一致")
        push!(runs,x)
    end
    (;api,normal,event_case=ec,handoff,runs)
end

function r7_normal_evidence_tables(x)
    api=x.api;unpack(v,k)=Base.invokelatest(Base.invokelatest(getfield,api,:r7_unpack),v,k)
    d=x.normal.case.data;r=x.normal.result
    v=Dict(k=>unpack(r["values"],k) for k in keys(r["values"]))
    normal=NamedTuple[]
    chp=findall(g->g["kind"]=="CHP",d["devices"]);bes=findall(g->g["kind"]=="BES",d["devices"])
    for w in eachindex(d["probabilities"]),t in 1:d["periods"]
        push!(normal,(run_id=r["run_id"],t=t,scenario=w,probability=d["probabilities"][w],dt_h=d["dt_h"],
            P_PCC_MW=v["P_PCC"][t,w],P_CHP_MW=sum(v["P"][chp,t,w]),P_ch_MW=sum(v["P_ch"][bes,t,w]),P_dis_MW=sum(v["P_dis"][bes,t,w]),
            E_BES_start_MWh=sum(v["E_BES"][bes,t,w]),E_BES_end_MWh=sum(v["E_BES"][bes,t+1,w]),H_source_MW=sum(v["H"][:,t,w]),
            E_S_start_MWh=sum(v["E_pipe_S"][:,t,w]),E_R_start_MWh=sum(v["E_pipe_R"][:,t,w]),
            E_S_end_MWh=sum(v["E_pipe_S"][:,t+1,w]),E_R_end_MWh=sum(v["E_pipe_R"][:,t+1,w])))
    end
    events=NamedTuple[]
    for xrun in x.runs
        rr=xrun.result;val=xrun.validation
        push!(events,(run_id=rr["run_id"],fault=join(rr["fault"],","),status=rr["status"],model_pass=val["model_pass"],
            loss_optimization_complete=rr["loss_optimization_complete"],loss_electric_MWh=get(val,"loss_electric_MWh",missing),
            loss_heat_MWh=get(val,"loss_heat_MWh",missing),loss_MWh=get(val,"loss_MWh",missing),lower_bound_MWh=get(rr,"lower_bound_MWh",missing),
            elapsed_sec=rr["elapsed_sec"],detailed_heat_validated=val["detailed_heat_validated"],ac_grid_validated=val["ac_grid_validated"]))
    end
    function csv(rows)
        csv_io=IOBuffer();CSV.write(csv_io,rows);String(take!(csv_io))
    end
    summary=Dict("schema"=>"r7-normal-development-evidence-v1","origin"=>d["origin"],"normal_run_id"=>r["run_id"],"normal_case_sha256"=>x.normal.case.sha256,
        "event_case_sha256"=>x.event_case.sha256,"normal_cost_USD"=>x.normal.validation["cost_USD"],"normal_model_pass"=>x.normal.validation["model_pass"],
        "conditional_cost_complete"=>r["conditional_cost_complete"],"normal_pipe_reference_pass"=>x.normal.validation["pipe_reference_pass"],
        "event_records"=>length(x.runs),"event_model_pass"=>count(y->y.validation["model_pass"],x.runs),
        "full_preplan_optimality_verified"=>false,"complete_R7_verified"=>false,"reoptimized_during_check"=>false)
    summary_io=IOBuffer();TOML.print(summary_io,summary;sorted=true)
    Dict("normal-trajectory.csv"=>csv(normal),"event-summary.csv"=>csv(events),"summary.toml"=>String(take!(summary_io)))
end

function r7_normal_evidence(args)
    if length(args)==3 && args[1]=="copy-report"
        source,dest=abspath(args[2]),abspath(args[3])
        ispath(dest) && error("不覆盖已有报告")
        r7_evidence_check_files(source,TOML.parsefile(joinpath(source,"evidence-files.toml"))["files"])
        r7_normal_evidence_values(source)
        mkpath(dest)
        for name in ("normal","event")
            cp(joinpath(source,name),joinpath(dest,name))
            r7_evidence_hashes(joinpath(source,name))==r7_evidence_hashes(joinpath(dest,name)) || error("原值续接改变了文件")
        end
        # 只修复报告载体；已优化的原值、输入、源码与历史失败均不重写。
        open(joinpath(dest,"continuation.toml"),"w") do io
            TOML.print(io,Dict("schema"=>"r7-normal-report-continuation-v1",
                "parent_manifest_sha256"=>bytes2hex(sha256(read(joinpath(source,"evidence-files.toml")))),
                "original_run_files_identical"=>true,"reoptimized"=>false,
                "reason"=>"Fix empty summary buffer and Julia 1.12 dynamic-module loading in report only");sorted=true)
        end
        return r7_normal_evidence(["create",dest])
    end
    length(args)==2 && args[1] in ("create","check") || error("r7_normal_evidence.jl create|check BUNDLE; copy-report OLD NEW")
    action,dir=args
    if action=="check"
        r7_evidence_check_files(dir,TOML.parsefile(joinpath(dir,"evidence-files.toml"))["files"])
    else
        any(ispath(joinpath(dir,p)) for p in ("evidence-files.toml","summary.toml","normal-trajectory.csv","event-summary.csv")) && error("不覆盖旧证据表")
    end
    x=r7_normal_evidence_values(dir);expected=r7_normal_evidence_tables(x)
    for (p,text) in expected
        if action=="create"
            write(joinpath(dir,p),text)
        else
            read(joinpath(dir,p),String)==text || error("原值与汇总不一致：$p")
        end
    end
    if action=="create"
        # 记录生成/重验脚本，后续可在冻结科学模块下逐条原值回代。
        mkpath(joinpath(dir,"workflow"));cp(@__FILE__,joinpath(dir,"workflow","r7_normal_evidence.jl"))
        io=IOBuffer();TOML.print(io,Dict("files"=>r7_evidence_hashes(dir));sorted=true)
        write(joinpath(dir,"evidence-files.toml"),take!(io))
    end
    println("R7 normal/event original values checked; conditional model only; no optimization")
    x
end

abspath(PROGRAM_FILE)==(@__FILE__) && r7_normal_evidence(ARGS)
