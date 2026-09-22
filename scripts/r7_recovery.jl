using PaperRebuild, JuMP, HiGHS, TOML

# 本入口只运行给定边界恢复；不生成灾前最优计划，不把开发手算例写成论文算例。
root=normpath(joinpath(@__DIR__, ".."))
usage="r7_recovery.jl solve <case.toml> <0,1,...> <new-run> | check <run>"
isempty(ARGS) && error(usage)
if ARGS[1]=="check" && length(ARGS)==2
    r=read_r7_recovery(ARGS[2])
    println("status=", r.result["status"], " model=", r.validation["model_pass"])
elseif ARGS[1]=="solve" && length(ARGS)==4
    c=load_r7_recovery_case(ARGS[2])
    fault=parse.(Int, split(ARGS[3], ','))
    opt=optimizer_with_attributes(
        HiGHS.Optimizer,
        "threads"=>1,
        "primal_feasibility_tolerance"=>1e-9,
        "dual_feasibility_tolerance"=>1e-9,
        "mip_feasibility_tolerance"=>1e-9,
        "mip_rel_gap"=>1e-9,
    )
    r=solve_r7_recovery(c, fault; optimizer = opt, budget_sec = 60)
    save_r7_recovery(c, r, ARGS[4])
    println(
        "status=",
        r["status"],
        " model=",
        r["candidate_accepted"],
        " expected_unserved_MWh=",
        get(r["validation"], "loss_MWh", "unavailable"),
    )
else
    error(usage)
end
