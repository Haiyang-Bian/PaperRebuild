# 只重建模型并代入保存值；本入口不安装求解器、不优化、不修改父实验。
using JuMP, TOML, SHA, CSV
include("r8_archive.jl")

function r8_embedding_check(report, evidence)
    items, _, _=r8_archive_inputs(report)
    manifest=TOML.parsefile(joinpath(evidence, "manifest.toml"))
    manifest["parent_manifest_sha256"]==r8_file_hash(joinpath(report, "report-hashes.toml")) ||
        error("父正式报告改变")
    files=r8_archive_files(evidence)
    delete!(files, "manifest.toml")
    files==manifest["files"] || error("嵌入补证文件被修改")
    M=r8_archive_module(report)
    protocol=TOML.parsefile(joinpath(evidence, "v2/protocol.toml"))
    protocol["science"]==TOML.parsefile(joinpath(report, "freeze.toml"))["science"] ||
        error("探针与正式源码不一致")
    protocol["parent_probe_protocol_sha256"]==r8_file_hash(joinpath(evidence, "v1/protocol.toml")) ||
        error("首版诊断身份改变")
    rows=NamedTuple[]
    for id in protocol["ids"]
        item=only(filter(x->x["id"]==id, items))
        raw=TOML.parsefile(joinpath(evidence, "v2", id*".toml"))
        old=TOML.parsefile(joinpath(evidence, "v1", id*".toml"))
        old["status"]=="probe_error" && occursin("atol", old["error"]) || error("首版失败记录丢失")
        parent=only(filter(x->x["id"]==raw["parent_id"], items))
        parent["case_sha256"]==item["case_sha256"] || error("不是同案例嵌入")
        for key in ("mode", "solver", "resource", "limit_MWh")
            parent[key]==item[key] || error("未声明的配对差异：$key")
        end
        parent["control"]=="fixed" && item["control"]=="joint_continuous" || error("流量域配对错误")
        Base.invokelatest() do
            c=M.R7PlanningCase(M.R7NormalCase(item["normal"]), item["planning"])
            p=r8_archive_record(report, parent, M).result["primary"]
            failed=r8_archive_record(report, item, M).result["primary"]
            failed["status"]=="time_limit_no_solution" || error("原正式限时状态变化")
            raw["parent_stage_run_id"]==p["run_id"] || error("父阶段身份错误")
            b=M.build_r8_model(c, item["flow"], item["spec"])
            vars=all_variables(b.model)
            saved=raw["all_solver_variables"]
            length(vars)==length(saved)==raw["model_variable_count"] || error("完整辅助值缺失")
            point=Dict{VariableRef,Float64}()
            for (v, row) in zip(vars, saved)
                index(v).value==row["index"] && name(v)==row["name"] || error("重建变量身份不一致")
                isfinite(row["value"]) || error("非有限原值")
                point[v]=row["value"]
            end
            # 重建的是原自由域，未调用fix：包括原始边界、整数域及全部非线性辅助关系。
            residuals=primal_feasibility_report(b.model, point; atol=0.0)
            maxres=maximum(values(residuals); init=0.0)
            maxres<=1e-8 || error("原自由模型关系不满足")
            candidate=raw["reconstructed_values"]
            q=M.r8_validate_stage(c, item["flow"], item["spec"], candidate)
            q==raw["independent_validation"] && q["model_pass"] || error("独立物理回放不一致")
            preservation=Float64[]
            function check(v, actual, expected)
                Set(keys(v))==Set(keys(actual))==Set(keys(expected)) || error("保存物理量字段不完整")
                for (key, a) in v
                    av, ev=M.r7_unpack(actual, key), M.r7_unpack(expected, key)
                    size(a)==size(av)==size(ev) || error("保存物理量形状不符")
                    for I in CartesianIndices(a)
                        value_here=a[I] isa Real ? a[I] : point[a[I]]
                        push!(preservation, abs(value_here-ev[I]), abs(av[I]-ev[I]))
                    end
                end
            end
            check(b.normal_variables, candidate["normal"]["values"], p["normal"]["values"])
            check(b.normal_flow, candidate["normal"]["flow_values"], p["normal"]["flow_values"])
            for (key, v) in b.chp_variables
                check(v, candidate["normal"]["chp_values"][key], p["normal"]["chp_values"][key])
            end
            for w in b.recovery
                pick(xs)=only(filter(x->x["event"]==w.pair.event&&x["fault"]==w.pair.fault, xs))
                cw, pw=pick(candidate["witnesses"]), pick(p["witnesses"])
                for (v, key) in ((w.variables,"values"),(w.thermal_variables,"thermal_values"),(w.boundary_parameters,"boundary_values"))
                    check(v, cw[key], pw[key])
                end
            end
            for (k, v) in enumerate(b.eta)
                push!(preservation, abs(point[v]-p["eta_MWh"][k]), abs(candidate["eta_MWh"][k]-p["eta_MWh"][k]))
            end
            delta=maximum(preservation; init=0.0)
            delta==raw["max_preservation_error"]==0.0 || error("物理值被改写")
            raw["status"]==raw["solver_termination"]=="OPTIMAL" || error("辅助求解状态不符")
            raw["elapsed_sec"]<=protocol["budget_sec"] || error("诊断超过冻结预算")
            push!(rows, (;id,parent_id=parent["id"],variables=length(vars),fixed_variables=raw["fixed_variable_count"],maximum_violation=maxres,preservation_error=delta,adopted_model_pass=q["model_pass"],elapsed_sec=raw["elapsed_sec"],formal_status=failed["status"]))
        end
    end
    length(rows)==4 || error("嵌入诊断数量错误")
    rows
end

function r8_embedding_freeze(report, v1, v2, destination)
    ispath(destination) && error("不覆盖嵌入证据")
    r8_archive_check(report)
    mkpath(destination)
    for (label, source) in (("v1",v1),("v2",v2))
        cp(source,joinpath(destination,label))
    end
    cp(@__FILE__,joinpath(destination,"replay-source.jl"))
    manifest=Dict("schema"=>"r8-embedding-evidence-v1","origin"=>"synthetic",
        "parent_manifest_sha256"=>r8_file_hash(joinpath(report,"report-hashes.toml")),
        "scope"=>"Original free-domain feasibility at fixed saved physical values; no claim of free-flow optimality or solver speed.",
        "files"=>r8_archive_files(destination))
    write_manifest()=open(joinpath(destination,"manifest.toml"),"w") do io
        TOML.print(io,manifest; sorted=true)
    end
    write_manifest()
    rows=r8_embedding_check(report,destination)
    CSV.write(joinpath(destination,"summary.csv"),rows)
    manifest["files"]["summary.csv"]=r8_file_hash(joinpath(destination,"summary.csv"))
    write_manifest()
    println("Frozen four unchanged physical witnesses; rebuilt original free-domain constraints and replayed physics without optimization.")
end

if abspath(PROGRAM_FILE)==@__FILE__
    if length(ARGS)==6 && ARGS[1]=="freeze"
        error("usage: freeze REPORT V1 V2 DESTINATION")
    elseif length(ARGS)==5 && ARGS[1]=="freeze"
        r8_embedding_freeze(abspath.(ARGS[2:5])...)
    elseif length(ARGS)==3 && ARGS[1]=="check"
        rows=r8_embedding_check(abspath(ARGS[2]),abspath(ARGS[3]))
        io=IOBuffer(); CSV.write(io,rows)
        take!(io)==read(joinpath(ARGS[3],"summary.csv")) || error("汇总与原值不一致")
        println("Four embedding witnesses independently passed; original formal timeout statuses preserved.")
    else
        error("usage: freeze REPORT V1 V2 DESTINATION | check REPORT EVIDENCE")
    end
end
