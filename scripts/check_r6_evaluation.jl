using PaperRebuild

if abspath(PROGRAM_FILE)==(@__FILE__)
    1<=length(ARGS)<=2 || error("usage: check_r6_evaluation.jl <directory> [--diagnostic]")
    length(ARGS)==1 || ARGS[2]=="--diagnostic" || error("未知操作")
    x=length(ARGS)==2 ? read_r6_evaluation(ARGS[1]) : read_r6_policy_day(ARGS[1])
    println(
        "Outcome: ",
        x.validation["comfort_outcome"],
        "; cost complete: ",
        x.validation["cost_complete"],
    )
    println("Current sources match: ", x.current_source_matches)
end
