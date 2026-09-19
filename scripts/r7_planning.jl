using PaperRebuild, HiGHS, JuMP

function main(args)
    if length(args)==6 && args[1]=="run"
        _, normal, spec, method, out, budget=args
        ispath(out)&&error("不覆盖已有运行目录")
        optimizer=optimizer_with_attributes(
            HiGHS.Optimizer,
            "threads"=>1,
            "primal_feasibility_tolerance"=>1e-9,
            "dual_feasibility_tolerance"=>1e-9,
            "mip_feasibility_tolerance"=>1e-9,
            "mip_rel_gap"=>1e-9,
        )
        c=load_r7_planning_case(normal, spec)
        r=solve_r7_planning(
            c;
            optimizer,
            method = Symbol(method),
            budget_sec = parse(Float64, budget),
        )
        save_r7_planning(c, r, out)
        println(
            r["status"],
            " robust=",
            r["candidate_accepted"],
            " cost_complete=",
            r["conditional_cost_complete"],
        )
    elseif length(args)==2 && args[1]=="check"
        x=read_r7_planning(args[2])
        println(x.result["status"], " robust=", x.validation["robust_model_pass"])
    else
        error(
            "usage: r7_planning.jl run NORMAL SPEC extensive|finite_fault_ccg NEW_DIR BUDGET_SEC | check DIR",
        )
    end
end
main(ARGS)
