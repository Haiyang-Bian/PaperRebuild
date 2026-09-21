# 诊断单独计时，不重写正式方法，也不改变已冻结输入/求解器设置。
const R9_TRADING_CONFLICT_START=time_ns()/1e9
include("r9_trading_study.jl")
using JuMP, Gurobi, TOML, SHA

"""提取冻结集中SOCP的冲突子集；求解器冲突与独立解析证明分别记录。"""
function audit_r9_trading_conflict(study, out)
    ispath(out) && error("Do not overwrite diagnostic evidence")
    meta=R9TradingStudy.check_inputs(study)
    mkpath(out)
    cp(@__FILE__, joinpath(out, "audit-source.jl"))
    result=Dict{String,Any}(
        "schema"=>"r9-trading-conflict-v1",
        "input_sha256"=>meta["input_sha256"],
        "study_manifest_sha256"=>R9TradingStudy.hashfile(joinpath(study, "manifest.toml")),
        "audit_source_sha256"=>R9TradingStudy.hashfile(@__FILE__),
        "budget_sec"=>60,
        "origin"=>"synthetic",
        "stage"=>"central",
        "electric"=>"socp",
        "solver_options"=>meta["protocol"]["gurobi"],
        "input_or_model_changed"=>false,
        "independent_analytic_proof"=>false,
    )
    clock() = time_ns()/1e9
    remaining() = R9_TRADING_CONFLICT_START+60-clock()
    try
        lib=R9TradingStudy.library(joinpath(study, "code"))
        c=R9TradingStudy.call(lib, :load_r9_trading_case, joinpath(study, "input.toml"))
        environment=Gurobi.Env(Dict{String,Any}("OutputFlag"=>0))
        optimizer=optimizer_with_attributes(
            ()->Gurobi.Optimizer(environment),
            collect(result["solver_options"])...,
        )
        b=R9TradingStudy.call(lib, :build_r9_trading_model, c; optimizer)
        result["model_class"]=b.model_class
        result["model_types"]=b.model_types
        if remaining()>0
            set_time_limit_sec(b.model, remaining())
            optimize!(b.model)
            result["termination"]=string(termination_status(b.model))
            result["primal_status"]=string(primal_status(b.model))
            result["raw_status"]=raw_status(b.model)
            if termination_status(b.model)==MOI.INFEASIBLE && remaining()>0
                set_time_limit_sec(b.model, remaining())
                compute_conflict!(b.model)
                # 更新IIS剩余时限会使JuMP解缓存失效；读取刚计算的后端冲突属性，
                # 不读取旧解值，也不把参数改动误判成未执行冲突计算。
                result["conflict_status"]=string(MOI.get(backend(b.model), MOI.ConflictStatus()))
                mapping=Dict(cr=>(id, i) for (id, cs) in b.constraints for (i, cr) in enumerate(cs))
                rows=Dict{String,Any}[]
                unavailable=String[]
                for (F, S) in list_of_constraint_types(b.model)
                    for cr in all_constraints(b.model, F, S)
                        status=try
                            MOI.get(backend(b.model), MOI.ConstraintConflictStatus(), index(cr))
                        catch err
                            push!(unavailable, string(F, " in ", S, ": ", typeof(err)))
                            break
                        end
                        status==MOI.NOT_IN_CONFLICT && continue
                        obj=constraint_object(cr)
                        id, ordinal=get(mapping, cr, ("variable-bound-or-domain", 0))
                        row=Dict{String,Any}(
                            "equation"=>id,
                            "ordinal"=>ordinal,
                            "status"=>string(status),
                            "expression"=>string(cr),
                            "function_type"=>string(F),
                            "set_type"=>string(S),
                        )
                        if obj.func isa AffExpr || obj.func isa VariableRef
                            f=obj.func isa VariableRef ? AffExpr(0.0, obj.func=>1.0) : obj.func
                            row["constant"]=constant(f)
                            row["terms"]=[
                                Dict("variable"=>name(x), "coefficient"=>a) for
                                (a, x) in linear_terms(f)
                            ]
                            if obj.set isa Union{MOI.EqualTo,MOI.LessThan,MOI.GreaterThan}
                                row["bound"]=obj.set isa MOI.EqualTo ? obj.set.value :
                                             obj.set isa MOI.LessThan ? obj.set.upper :
                                             obj.set.lower
                            end
                        end
                        push!(rows, row)
                    end
                end
                result["constraints"]=rows
                result["unavailable_types"]=unavailable
                result["all_types_read"]=isempty(unavailable)
            end
        else
            result["termination"]="budget_before_optimize"
        end
    catch err
        err isa InterruptException && rethrow()
        result["error_type"]=string(typeof(err))
        result["error_category"]="diagnostic_incomplete"
        showerror(stderr, err, catch_backtrace())
        println(stderr)
    end
    result["elapsed_sec"]=clock()-R9_TRADING_CONFLICT_START
    result["budget_pass"]=result["elapsed_sec"]<=60
    R9TradingStudy.toml(joinpath(out, "audit.toml"), result)
    println(
        "Conflict: ",
        get(result, "conflict_status", "unavailable"),
        "; rows=",
        length(get(result, "constraints", [])),
        "; elapsed=",
        result["elapsed_sec"],
    )
    result
end

if abspath(PROGRAM_FILE)==@__FILE__
    length(ARGS)==2 || error("usage: audit_r9_trading_conflict.jl STUDY NEW_DIAGNOSTIC")
    audit_r9_trading_conflict(abspath(ARGS[1]), abspath(ARGS[2]))
end
