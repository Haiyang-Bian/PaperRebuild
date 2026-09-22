# 固定失败首块的等价表示诊断。独立保存原始状态、变量和乘子，不改历史调度。
module R9BoundProbe
push!(LOAD_PATH, normpath(joinpath(@__DIR__, "..")))
using PaperRebuild, JuMP, Gurobi, Clarabel, TOML, SHA, LinearAlgebra, Dates, Test
const MOI = JuMP.MOI
clock() = time_ns()/1e9
hashfile(path) = bytes2hex(open(sha256, path))
toml(path, data) = open(io -> TOML.print(io, data; sorted=true), path, "w")

"""将原JuMP表达式转为纯数字多项式；后续检查不调用优化器或表达式求值。"""
function polynomial(f, ids)
    d=Dict{String,Any}("constant"=>0.0,"linear_ids"=>Int[],"linear_coefficients"=>Float64[],
        "quadratic_i"=>Int[],"quadratic_j"=>Int[],"quadratic_coefficients"=>Float64[])
    if f isa VariableRef
        push!(d["linear_ids"], ids[f]); push!(d["linear_coefficients"], 1.0)
    elseif f isa Real
        d["constant"]=Float64(f)
    else
        d["constant"]=Float64(JuMP.constant(f))
        for (coefficient, v) in linear_terms(f)
            push!(d["linear_ids"], ids[v]); push!(d["linear_coefficients"], coefficient)
        end
        if f isa GenericQuadExpr
            for (coefficient, v, w) in quad_terms(f)
                push!(d["quadratic_i"], ids[v]); push!(d["quadratic_j"], ids[w])
                push!(d["quadratic_coefficients"], coefficient)
            end
        end
    end
    d
end

function rows(model)
    refs=Any[]
    for (F,S) in sort(list_of_constraint_types(model); by=x->string(x))
        append!(refs, all_constraints(model,F,S))
    end
    refs
end

"""完整记录目标、约束方向和变量身份；只支持本诊断实际使用的凸二次锥形式。"""
function snapshot(model)
    vars=all_variables(model)
    ids=Dict(v=>i for (i,v) in enumerate(vars))
    rs=Dict{String,Any}[]
    for r in rows(model)
        obj=constraint_object(r)
        set=obj.set
        kind=set isa MOI.EqualTo ? "equal" : set isa MOI.GreaterThan ? "lower" :
             set isa MOI.LessThan ? "upper" : set isa MOI.SecondOrderCone ? "soc" :
             set isa MOI.RotatedSecondOrderCone ? "rsoc" : error("Unsupported set: $set")
        rhs=kind=="equal" ? set.value : kind=="lower" ? set.lower : kind=="upper" ? set.upper : 0.0
        fs=obj.func isa AbstractVector ? obj.func : [obj.func]
        push!(rs, Dict("id"=>string(index(r)),"kind"=>kind,"rhs"=>Float64(rhs),
            "functions"=>[polynomial(f,ids) for f in fs]))
    end
    Dict("variables"=>name.(vars),"objective"=>polynomial(objective_function(model),ids),
         "constraints"=>rs)
end

function evaluate(p,x)
    z=p["constant"]
    for (i,a) in zip(p["linear_ids"],p["linear_coefficients"])
        z+=a*x[i]
    end
    for (i,j,a) in zip(p["quadratic_i"],p["quadratic_j"],p["quadratic_coefficients"])
        z+=a*x[i]*x[j]
    end
    z
end

function derivative(p,x)
    g=zeros(length(x))
    for (i,a) in zip(p["linear_ids"],p["linear_coefficients"])
        g[i]+=a
    end
    for (i,j,a) in zip(p["quadratic_i"],p["quadratic_j"],p["quadratic_coefficients"])
        g[i]+=a*x[j]; g[j]+=a*x[i]
    end
    g
end

"""RSOC经正交坐标变换得到SOC；此变换保持内积和锥的自对偶性质。"""
function cone_error(kind,z)
    kind=="soc" && return max(0.0,norm(z[2:end])-z[1])
    kind=="rsoc" && return max(0.0,norm([(z[1]-z[2])/sqrt(2);z[3:end]])-(z[1]+z[2])/sqrt(2))
    error("Not a cone")
end

"""独立重算原点的原始/对偶/互补/驻点残差；不生成全局下界或覆盖求解器状态。"""
function replay(s,w)
    x=w["x"]
    length(x)==length(s["variables"]) || error("Point dimensions")
    all(isfinite,x) || error("Nonfinite point")
    station=derivative(s["objective"],x)
    denom=1 .+ abs.(station)
    pe=0.0; de=0.0; ce=0.0; rawpe=0.0
    rawduals=get(w,"raw_duals",Dict{String,Any}())
    complete=all(r->haskey(rawduals,r["id"]),s["constraints"])
    worst=""
    for r in s["constraints"]
        z=[evaluate(f,x) for f in r["functions"]]
        kind=r["kind"]
        slack=kind in ("equal","lower","upper") ? z .- r["rhs"] : z
        violation=kind=="equal" ? abs(slack[1]) : kind=="lower" ? max(0.0,-slack[1]) :
                  kind=="upper" ? max(0.0,slack[1]) : cone_error(kind,z)
        rawpe=max(rawpe,violation)
        normpe=violation/max(1.0,norm(z),norm(slack))
        normpe>pe && (pe=normpe;worst=r["id"])
        if haskey(rawduals,r["id"])
            y=rawduals[r["id"]]
            length(y)==length(z) && all(isfinite,y) || error("Invalid raw multiplier")
            violation=kind=="equal" ? 0.0 : kind=="lower" ? max(0.0,-y[1]) :
                      kind=="upper" ? max(0.0,y[1]) : cone_error(kind,y)
            de=max(de,violation/max(1.0,norm(y)))
            ce=max(ce,abs(dot(slack,y))/max(1.0,norm(slack)*norm(y)))
            for (f,yi) in zip(r["functions"],y)
                dg=derivative(f,x)
                station.-=yi.*dg; denom.+=abs.(yi.*dg)
            end
        end
    end
    obj=evaluate(s["objective"],x)
    report=w["reported_objective"]
    Dict("objective_at_primal"=>obj,"report_relative_error"=>abs(report-obj)/max(1,abs(report),abs(obj)),
        "primal_normalized"=>pe,"primal_raw_mixed_units"=>rawpe,"worst_primal_row"=>worst,
        "all_raw_duals_available"=>complete,"dual_normalized"=>complete ? de : NaN,
        "complementarity_normalized"=>complete ? ce : NaN,
        "stationarity_normalized"=>complete ? maximum(abs.(station)./denom) : NaN,
        "global_bound_certified"=>false,"diagnostic_only"=>true)
end

function capture(model)
    w=Dict{String,Any}("termination"=>string(termination_status(model)),
        "primal_status"=>string(primal_status(model)),"dual_status"=>string(dual_status(model)))
    if has_values(model)
        w["x"]=value.(all_variables(model))
        w["reported_objective"]=objective_value(model)
        w["raw_duals"]=Dict{String,Any}()
        w["unavailable_duals"]=Dict{String,Any}()
        for r in rows(model)
            try
                y=dual(r)
                w["raw_duals"][string(index(r))]=y isa AbstractVector ? collect(y) : [y]
            catch err
                w["unavailable_duals"][string(index(r))]=string(typeof(err))
            end
        end
        for (key,f) in (("dual_objective",dual_objective_value),("objective_bound",objective_bound))
            try
                w[key]=f(model)
            catch err
                w[key*"_unavailable"]=string(typeof(err))
            end
        end
    end
    w
end

function run(study,out)
    VERSION==v"1.12.6" || error("Julia version")
    ispath(out) && error("Preserve previous diagnostic")
    mkpath(out)
    begin_time=clock()
    p=TOML.parsefile(joinpath(study,"code/configs/r9/distributed-corridor-study.toml"))
    c=load_r9_trading_case(joinpath(study,"inputs/equipment-fixed.toml"))
    m=Dict(k=>PaperRebuild.r4_matrix(v) for (k,v) in TOML.parsefile(joinpath(study,"fixed-modes.toml")))
    source_hashes=PaperRebuild.r9_trading_science_hashes()
    original=TOML.parsefile(joinpath(study,"manifest.toml"))
    environment_difference=String[]
    for (path,h) in source_hashes
        if original["files"]["code/"*path]!=h
            path=="Project.toml" || error("Scientific code changed: $path")
            old=TOML.parsefile(joinpath(study,"code",path))
            current=TOML.parsefile(path)
            all(k->old[k]==current[k],("deps","compat")) || error("Runtime dependencies changed")
            push!(environment_difference,"Project.toml test extras/target only; runtime deps/compat/lock unchanged")
        end
    end
    rawpath=joinpath(study,"runs/fixed-convex-admm/raw-result.toml")
    raw=TOML.parsefile(rawpath)
    original_block=only(raw["last_attempt"]["agents"])
    original_block["actor"]==2 && isempty(raw["trace"]) || error("Expected first failed block")
    rules=Dict("schema"=>"r9-bound-representation-probe-v1","origin"=>"synthetic",
        "actor"=>2,"rho"=>1.0,"initialization"=>"zero_target_and_dual",
        "variants"=>["Clarabel_original","Clarabel_exact_fix","Gurobi_original","Gurobi_exact_fix"],
        "transformation"=>"Only finite exactly equal lower/upper bounds become EqualTo; no rounding",
        "global_budget_sec"=>600.0,"per_variant_solve_budget_sec"=>60.0,
        "source_hashes"=>source_hashes,"probe_sha256"=>hashfile(@__FILE__),
        "environment_difference"=>environment_difference,
        "input_sha256"=>c.sha256,"modes_sha256"=>hashfile(joinpath(study,"fixed-modes.toml")),
        "parent_manifest_sha256"=>hashfile(joinpath(study,"manifest.toml")),
        "parent_raw_sha256"=>hashfile(rawpath),"created_utc"=>string(now(UTC)),
        "gurobi_dual_collection"=>"QCPDual=1 equally on both Gurobi variants",
        "thresholds_unchanged"=>true,"historical_state_rewritten"=>false)
    toml(joinpath(out,"rules.toml"),rules)
    write(joinpath(out,"input.toml"),c.source_text)
    cp(joinpath(study,"fixed-modes.toml"),joinpath(out,"fixed-modes.toml"))
    cp(@__FILE__,joinpath(out,"probe.jl"))
    toml(joinpath(out,"parent-block.toml"),original_block)
    summaries=Dict{String,Any}[]
    env=Gurobi.Env(Dict{String,Any}("OutputFlag"=>0))
    base_snapshot=nothing
    for id in rules["variants"]
        start=clock()
        start-begin_time>=600 && break
        kind=startswith(id,"Clarabel") ? "clarabel" : "gurobi"
        options=deepcopy(p[kind])
        kind=="gurobi" && (options["QCPDual"]=1)
        factory=kind=="clarabel" ? optimizer_with_attributes(Clarabel.Optimizer,collect(options)...) :
            optimizer_with_attributes(()->Gurobi.Optimizer(env),collect(options)...)
        b=build_r9_distributed_block(c;actor=2,modes=m,optimizer=factory)
        PaperRebuild.r9_distributed_objective!(b,zeros(size(b.message)),zeros(size(b.message)),raw["cost_scale"],1.0)
        initial=snapshot(b.model)
        if base_snapshot===nothing
            base_snapshot=initial
            toml(joinpath(out,"original-model.toml"),initial)
        else
            @test initial==base_snapshot
        end
        exact_bounds=Dict{String,Any}[]
        for (i,v) in enumerate(all_variables(b.model))
            if !is_fixed(v) && has_lower_bound(v) && has_upper_bound(v) &&
               isfinite(lower_bound(v)) && lower_bound(v)==upper_bound(v)
                push!(exact_bounds,Dict("index"=>i,"name"=>name(v),"value"=>lower_bound(v)))
                endswith(id,"exact_fix") && fix(v,lower_bound(v);force=true)
            end
        end
        s=snapshot(b.model)
        folder=joinpath(out,id);mkpath(folder)
        toml(joinpath(folder,"model.toml"),s)
        toml(joinpath(folder,"equal-bounds.toml"),Dict("variables"=>exact_bounds))
        record=Dict{String,Any}("id"=>id,"options"=>options,"variable_count"=>num_variables(b.model),
            "constraint_count"=>length(s["constraints"]),"equal_bound_count"=>length(exact_bounds),
            "same_initial_model"=>true,"new_full_admm_run"=>false)
        set_silent(b.model)
        set_time_limit_sec(b.model,min(60.0,max(0.001,600-(clock()-begin_time))))
        try
            optimize!(b.model)
            w=capture(b.model)
            w["solver_version"]=string(MOI.get(backend(b.model),MOI.SolverVersion()))
            toml(joinpath(folder,"witness.toml"),w)
            record["termination"]=w["termination"]
            record["primal_status"]=w["primal_status"]
            record["dual_status"]=w["dual_status"]
            if haskey(w,"x")
                checked=replay(s,w)
                toml(joinpath(folder,"replay.toml"),checked)
                record["replay"]=checked
                record["original_primal_normalized"]=replay(base_snapshot,Dict(
                    "x"=>w["x"],"reported_objective"=>w["reported_objective"]))["primal_normalized"]
            end
        catch err
            err isa InterruptException && rethrow()
            record["error"]=sprint(showerror,err)
            record["status"]="diagnostic_error"
        end
        record["elapsed_sec"]=clock()-start
        toml(joinpath(folder,"record.toml"),record)
        open(io->print_active_bridges(io,b.model),joinpath(folder,"bridges.txt"),"w")
        push!(summaries,record)
        println(id," ",get(record,"termination",get(record,"status","unknown")),
            " equal_bounds=",length(exact_bounds)," objective=",get(get(record,"replay",Dict()),"objective_at_primal",NaN))
        flush(stdout)
    end
    @test source_hashes==PaperRebuild.r9_trading_science_hashes()
    toml(joinpath(out,"summary.toml"),Dict("variants"=>summaries,"elapsed_sec"=>clock()-begin_time,
        "complete"=>length(summaries)==4,"historical_results_changed"=>false))
end

end
if abspath(PROGRAM_FILE)==@__FILE__
    length(ARGS)==2 || error("Usage: STUDY NEW_OUTPUT")
    R9BoundProbe.run(ARGS...)
end
