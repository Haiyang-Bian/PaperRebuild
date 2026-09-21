# 固定的新诊断协议：状态消歧、可开机数量上界、必要时固定首步开机的IIS。旧运行不改。
const AUDIT_STARTED=time()
using PaperRebuild, JuMP, Gurobi, TOML, SHA, UUIDs
include("r9_preplan_study.jl")
const PR=PaperRebuild
function audit_conflict(b, deadline)
    result=Dict{String,Any}("rows"=>Any[], "unavailable"=>String[])
    time()<deadline || return result
    set_time_limit_sec(b.model, deadline-time())
    compute_conflict!(b.model)
    result["status"]=string(MOI.get(backend(b.model), MOI.ConflictStatus()))
    mapping=Dict(cr=>(id, i) for (id, cs) in b.constraints for (i, cr) in enumerate(cs))
    for (F, S) in list_of_constraint_types(b.model), cr in all_constraints(b.model, F, S)
        status=try
            MOI.get(backend(b.model), MOI.ConstraintConflictStatus(), index(cr))
        catch err
            push!(result["unavailable"], string(F, " in ", S, " ", typeof(err)))
            continue
        end
        status==MOI.NOT_IN_CONFLICT && continue
        id, k=get(mapping, cr, ("variable-bound-or-added-pin", 0))
        object=constraint_object(cr)
        row=Dict{String,Any}(
            "formula"=>id,
            "ordinal"=>k,
            "status"=>string(status),
            "expression"=>string(cr),
        )
        if object.func isa Union{AffExpr,VariableRef}
            f=object.func isa VariableRef ? AffExpr(0.0, object.func=>1.0) : object.func
            row["constant"]=f.constant
            row["terms"]=[Dict("variable"=>name(v), "coefficient"=>a) for (v, a) in f.terms]
        end
        push!(result["rows"], row)
    end
    result["unavailable"]=unique(result["unavailable"])
    result
end
function main(input, out)
    ispath(out) && error("不覆盖诊断")
    x=R9PreplanStudy.readinput(input)
    c=x.case
    isfinite(AUDIT_STARTED) || error("无效时钟")
    mkpath(out)
    sources=merge(
        R9PreplanStudy.science(),
        Dict("scripts/audit_r9_preplan_commitment.jl"=>@__FILE__),
    )
    for (p, file) in sources
        dest=joinpath(out, "code", p)
        mkpath(dirname(dest))
        cp(file, dest)
    end
    sourcehashes=Dict(k=>R9PreplanStudy.hashfile(v) for (k, v) in sources)
    protocol=Dict(
        "schema"=>"r9-preplan-commitment-audit-v1",
        "input_manifest_sha256"=>R9PreplanStudy.hashfile(joinpath(input, "files.toml")),
        "budget_sec"=>180.0,
        "threshold_deadline_sec"=>75.0,
        "max_on_deadline_sec"=>130.0,
        "pin_iis_deadline_sec"=>170.0,
        "device"=>"CHP1",
        "order"=>[
            "fresh_threshold_DualReductions_0",
            "maximize_event_CHP1_on_steps",
            "pin_first_event_step_then_IIS_if_maximum_zero",
        ],
        "source_hashes"=>sourcehashes,
        "reference"=>"https://support.gurobi.com/hc/en-us/articles/4402704428177-How-do-I-resolve-the-error-Model-is-infeasible-or-unbounded",
    )
    write(joinpath(out, "protocol.toml"), PR.r7_text(protocol))
    opt=optimizer_with_attributes(
        Gurobi.Optimizer,
        "OutputFlag"=>0,
        "Threads"=>1,
        "DualReductions"=>0,
        "FeasibilityTol"=>1e-9,
        "IntFeasTol"=>1e-9,
        "OptimalityTol"=>1e-9,
        "MIPGap"=>1e-4,
    )
    s=TOML.parsefile(joinpath(input, "threshold-spec.toml"))
    stop=AUDIT_STARTED+75
    r=solve_r9_preplan(c, s; optimizer = opt, budget_sec = max(0, stop-time()), deadline = stop)
    save_r9_preplan(c, s, r, joinpath(out, "threshold-clarified"))
    println("Fresh threshold status: ", r["status"])
    flush(stdout)
    a=Dict{String,Any}(
        "status"=>"budget_exhausted",
        "objective_kind"=>"maximum_CHP1_committed_event_steps",
    )
    stop=AUDIT_STARTED+130
    if time()<stop
        b=build_r7_normal(c.normal; optimizer = opt)
        normalcost=objective_function(b.model)
        ev=only(c.specification["events"])
        win=ev["event_start"]:(ev["event_start"]+ev["periods"]-1)
        u=b.chp["CHP1"].variables["u_CHP"]
        @objective(b.model, Max, sum(u[t] for t in win))
        set_silent(b.model)
        if time()<stop
            set_time_limit_sec(b.model, stop-time())
            optimize!(b.model)
            a["status"]=string(termination_status(b.model))
            if has_values(b.model)
                a["on_steps"]=objective_value(b.model)
                a["on_steps_upper_bound"]=objective_bound(b.model)
                a["commitment"]=value.(u)
                # 只借用数值适配器，正常子记录仍保存真实运行费用；最大开机目标另列。
                adapted=(;
                    normal_variables = b.variables,
                    chp_variables = Dict(k=>v.variables for (k, v) in b.chp),
                    normal_cost = normalcost,
                    included = [],
                    recovery = [],
                    ζ = VariableRef[],
                )
                n=PR.r9_preplan_snapshot(adapted, c, s, "r9-on-audit-"*string(uuid4())).master["normal"]
                a["normal"]=n
                a["normal_validation"]=validate_r7_normal(c.normal, n)
                a["objective_replay"]=sum(PR.r7_unpack(n["chp_values"]["CHP1"], "u_CHP")[win])
            end
            println(
                "CHP1 maximum event steps: ",
                get(a, "on_steps", NaN),
                " bound=",
                get(a, "on_steps_upper_bound", NaN),
            )
            flush(stdout)
            write(joinpath(out, "max-on.toml"), PR.r7_text(a))
            if get(a, "on_steps_upper_bound", Inf)<0.5 && time()<AUDIT_STARTED+170
                @constraint(b.model, u[first(win)]==1)
                @objective(b.model, Min, normalcost)
                set_time_limit_sec(b.model, AUDIT_STARTED+170-time())
                optimize!(b.model)
                pin=Dict{String,Any}(
                    "status"=>string(termination_status(b.model)),
                    "event_step"=>first(win),
                    "device"=>"CHP1",
                    "pin_value"=>1,
                )
                if termination_status(b.model)==MOI.INFEASIBLE && time()<AUDIT_STARTED+170
                    pin["conflict"]=audit_conflict(b, AUDIT_STARTED+170)
                end
                write(joinpath(out, "pin-conflict.toml"), PR.r7_text(pin))
                println("Pinned first-step status: ", pin["status"])
                flush(stdout)
            end
        end
    end
    isfile(joinpath(out, "max-on.toml")) || write(joinpath(out, "max-on.toml"), PR.r7_text(a))
    all(R9PreplanStudy.hashfile(sources[k])==h for (k, h) in sourcehashes) ||
        error("诊断中源码改变")
    record=Dict(
        "files"=>R9PreplanStudy.filehashes(out),
        "total_wall_sec"=>time()-AUDIT_STARTED,
        "budget_pass"=>time()-AUDIT_STARTED<=180,
        "whole_fault_claim"=>false,
    )
    write(joinpath(out, "audit.toml"), PR.r7_text(record))
    println("Audit wall seconds: ", record["total_wall_sec"])
end
length(ARGS)==2 || error("usage: audit_r9_preplan_commitment.jl FROZEN_INPUT NEW_AUDIT")
main(abspath(ARGS[1]), abspath(ARGS[2]))
