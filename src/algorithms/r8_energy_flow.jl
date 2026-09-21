function r8_energy_snapshot(b, c, id)
    pack(a) = r7_pack(value.(a))
    n=Dict{String,Any}(
        "schema"=>r7_money_schema(c.normal.data, "r8-energy-normal-v1"),
        "run_id"=>id*"-normal",
        "case_sha256"=>c.normal.sha256,
        "values"=>Dict(k=>pack(a) for (k, a) in b.normal_variables),
        "energy_values"=>Dict("H_pipe"=>pack(b.normal_heat_flow)),
        "chp_values"=>Dict(id=>Dict(k=>pack(a) for (k, a) in v) for (id, v) in b.chp_variables),
        r7_money_key(c.normal.data, "normal_cost_USD")=>value(b.normal_cost),
    )
    r7_currency_record!(n, c.normal.data)
    witnesses=[
        Dict(
            "event"=>w.pair.event,
            "fault"=>w.pair.fault,
            "witness_loss_MWh"=>value(w.loss),
            "values"=>Dict(k=>pack(a) for (k, a) in w.variables),
            "boundary_values"=>Dict(k=>pack(a) for (k, a) in w.boundary_parameters),
            "energy_values"=>Dict("H_pipe"=>pack(w.heat_flow)),
        ) for w in b.recovery
    ]
    (; normal = n, witnesses, eta = value.(b.eta))
end

function r8_energy_stage(c, s; optimizer, deadline, normal_result = nothing)
    started=time()
    evaluation=normal_result!==nothing
    id="r8-energy-stage-"*string(uuid4())
    r=Dict{String,Any}(
        "run_id"=>id,
        "status"=>"budget_exhausted",
        "evaluation"=>evaluation,
        "objective_kind"=>r8_objective_kind(s; evaluation),
    )
    r7_currency_record!(r, c.normal.data)
    evaluation && (r["fixed_normal_sha256"]=r7_digest(normal_result))
    if time()<deadline
        try
            b=build_r8_energy_model(c, s; optimizer, deadline, normal_result)
            r["build_sec"]=time()-started
            r["model_class"], r["model_types"]=b.model_class, b.model_types
            if time()<deadline
                set_silent(b.model)
                set_time_limit_sec(b.model, deadline-time())
                optimize!(b.model)
                ts, pr=termination_status(b.model), primal_status(b.model)
                r["termination_status"], r["primal_status"]=string(ts), string(pr)
                r["raw_status"], r["solver_name"]=raw_status(b.model), solver_name(b.model)
                r["status"]=ts==MOI.INFEASIBLE ? "infeasible_certified" :
                            ts==MOI.TIME_LIMIT ? "time_limit_no_solution" :
                            "solver_"*lowercase(string(ts))
                if has_values(b.model)&&pr in (MOI.FEASIBLE_POINT, MOI.NEARLY_FEASIBLE_POINT)
                    x=r8_energy_snapshot(b, c, id)
                    r["normal"], r["witnesses"], r["eta_MWh"]=x.normal, x.witnesses, x.eta
                    r["solver_objective"]=objective_value(b.model)
                    r["status"]=ts==MOI.TIME_LIMIT ? "time_limit_with_solution" : "candidate"
                end
                try
                    bound=objective_bound(b.model)
                    isfinite(bound) ? (r["objective_lower_bound"]=bound) :
                    (r["bound_unavailable"]="nonfinite")
                catch err
                    r["bound_unavailable"]=sprint(showerror, err)
                end
            end
        catch err
            msg=sprint(showerror, err)
            r["status"]=occursin("license", lowercase(msg)) ? "license_unavailable" :
                        occursin("build_deadline", msg) ? "budget_exhausted" : "solver_error"
            r["error"]=msg
        end
    end
    r["validation"]=r8_energy_stage_check(c, s, r; normal_result)
    r["elapsed_sec"]=time()-started
    r
end

"""
    solve_r8_energy_case(case, spec; optimizer, budget_sec=600)

在同一墙钟预算内求稳态能流主目标，再固定全部正常原值评估最坏恢复失供。
主问题最多80%，最后预留10%（至多60秒）供独立核验。保存失败/无界/限时及原始值，
不自动转用详细动态热网、不把稳态可行当动态可行；不写文件。
"""
function solve_r8_energy_case(c::R7PlanningCase, s; optimizer, budget_sec = 600.0)
    r8_energy_check(c, s)
    isfinite(budget_sec)&&budget_sec>=0 || error("稳态能流预算错误")
    started=time()
    stop=started+budget_sec
    hashes=r8_energy_science_hashes()
    r=Dict{String,Any}(
        "schema"=>r7_money_schema(c.normal.data, "r8-energy-result-v1"),
        "version"=>s["version"],
        "run_id"=>"r8-energy-"*string(uuid4()),
        "case_sha256"=>c.sha256,
        "spec_sha256"=>r7_digest(s),
        "source_hashes_at_solve"=>hashes,
        "budget_sec"=>Float64(budget_sec),
        "julia_version"=>string(VERSION),
        "full_thesis_domain_verified"=>false,
    )
    r7_currency_record!(r, c.normal.data)
    r["primary"]=r8_energy_stage(c, s; optimizer, deadline = started+0.8budget_sec)
    if r["primary"]["validation"]["model_pass"]
        r["evaluation"]=r8_energy_stage(
            c,
            s;
            optimizer,
            deadline = stop-min(60.0, 0.1budget_sec),
            normal_result = r["primary"]["normal"],
        )
    end
    r["validation"]=validate_r8_energy_solution(c, s, r)
    r["elapsed_sec"]=time()-started
    r["budget_overrun_sec"]=max(0.0, time()-stop)
    r["wall_budget_pass"]=r["budget_overrun_sec"]==0.0
    hashes==r8_energy_science_hashes() || error("求解期间稳态科学源码改变")
    r
end

function r8_energy_science_hashes()
    root=normpath(joinpath(@__DIR__, "../.."))
    hashes=r8_science_hashes()
    for p in (
        "src/core/r8_energy_flow.jl",
        "src/formulations/r8_energy_flow.jl",
        "src/verification/r8_energy_flow.jl",
        "src/algorithms/r8_energy_flow.jl",
        "src/reporting/r8_energy_flow.jl",
    )
        hashes[p]=bytes2hex(sha256(read(joinpath(root, p))))
    end
    hashes
end
