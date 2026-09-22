"""
    build_r9_detailed_preplan(case, spec; optimizer=nothing, deadline=Inf)

R9-DP1/DP2：将同一灾前入口历史连接到各故障详细热模型，保留时间与空间温区。
恢复决策各自独立，CHP承诺、事前出力和初始管温共同决定；不使用任意均温替换。
罚费按事件最大失供计，门槛模式按逐故障见证计。返回实际LP/MILP类型，不求解、不写文件。
"""
function build_r9_detailed_preplan(c::R7PlanningCase, s; optimizer = nothing, deadline = Inf)
    time() < deadline || error("detailed_preplan_build_deadline")
    carrier = r9_detailed_preplan_check(c, s)
    base = s["base_spec"]
    selected = r9_preplan_pairs(base)
    included = base["mode"] == "economic" ? eltype(selected)[] : selected
    b = build_r7_linked_planning(carrier, s["linked_spec"]; optimizer, included, deadline)
    normal_cost = objective_function(b.model)
    ζ = VariableRef[]
    if base["mode"] == "penalty"
        caps = r8_loss_caps(c)
        ζ = @variable(
            b.model,
            [i in eachindex(caps)],
            lower_bound = 0,
            upper_bound = caps[i],
            base_name = "worst_detailed_loss_MWh"
        )
        # R9-DP2：故障是互为备选的实现，不能累加成多次同时发生的失供。
        for witness in b.recovery
            @constraint(b.model, ζ[witness.pair.event] >= witness.loss)
        end
        @objective(b.model, Min, normal_cost + base["penalty_MWh"] * sum(ζ))
    end
    types = list_of_constraint_types(b.model)
    all(
        F in (VariableRef, AffExpr) && S in (
            MOI.LessThan{Float64},
            MOI.GreaterThan{Float64},
            MOI.EqualTo{Float64},
            MOI.Interval{Float64},
            MOI.ZeroOne,
        ) for (F, S) in types
    ) || error("详细灾前出现未声明的非线性或锥约束")
    time() < deadline || error("detailed_preplan_build_deadline")
    model_types = [Dict("function" => string(F), "set" => string(S)) for (F, S) in types]
    (; b..., normal_cost, ζ, carrier, model_types)
end
