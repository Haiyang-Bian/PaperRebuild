push!(LOAD_PATH, normpath(joinpath(@__DIR__, "..")))
using PaperRebuild, JuMP
!isempty(ARGS) && ARGS[1] in ("run", "plan") && (@eval import Gurobi)

function r7_inner_factory()
    env=Gurobi.Env(Dict{String,Any}("OutputFlag"=>0))
    optimizer_with_attributes(
        ()->Gurobi.Optimizer(env),
        "Threads"=>1,
        "Seed"=>0,
        "FeasibilityTol"=>1e-9,
        "OptimalityTol"=>1e-9,
        "IntFeasTol"=>1e-9,
        "MIPGap"=>1e-9,
        "DualReductions"=>0,
    )
end

function main(args)
    if length(args)==4 && args[1]=="run"
        _, input, out, budget=args
        ispath(out) && error("不覆盖已有运行")
        c=load_r7_recovery_case(input)
        r=solve_r7_adversary(c; optimizer = r7_inner_factory(), budget_sec = parse(Float64, budget))
        save_r7_adversary(c, r, out)
        println(r["status"], " ", r["validation"]["threshold_status"])
    elseif length(args)==5 && args[1]=="plan"
        _, normal, spec, out, budget=args
        ispath(out) && error("不覆盖已有规划")
        c=load_r7_planning_case(normal, spec)
        r=solve_r7_planning(
            c;
            optimizer = r7_inner_factory(),
            method = :nested_indicator_ccg,
            budget_sec = parse(Float64, budget),
        )
        save_r7_planning(c, r, out)
        println(r["status"], " robust=", r["candidate_accepted"])
    elseif length(args)==2 && args[1]=="check"
        # 用记录自己的源代码只读重验，可同时接受内层和嵌套规划记录。
        wrapper=Module(gensym(:R7Replay))
        Base.include(wrapper, abspath(joinpath(args[2], "code/replay.jl")))
    else
        error(
            "usage: r7_adversary.jl run CASE NEW_DIR SEC | plan NORMAL SPEC NEW_DIR SEC | check DIR",
        )
    end
end
main(ARGS)
