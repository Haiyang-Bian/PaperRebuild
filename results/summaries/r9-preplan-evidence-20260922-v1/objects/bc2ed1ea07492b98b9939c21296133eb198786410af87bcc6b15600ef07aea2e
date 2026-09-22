"""
    build_r9_preplan(case, spec; optimizer=nothing)

建立4A/4B/4C给定正常流量的联合灾前规划，不求解或写文件。复用R7共享启停/出力/热状态，
各故障具有独立恢复见证。R9-RP1保持正常模型；R9-RP2用逐事件上图变量表示最坏失供；
R9-RP3通过独立载体实施门槛。返回正常费用表达式和总目标，禁止将罚费界写成正常费用界。
恢复采用聚合热模型，正常仍为原连续逐管参考，未将其替换为Gauss共同流量模型。
"""
function build_r9_preplan(c::R7PlanningCase, s; optimizer = nothing)
    carrier=r9_preplan_carrier(c, s)
    selected=r9_preplan_pairs(s)
    included=s["mode"]=="economic" ? eltype(selected)[] : selected
    b=build_r7_planning(carrier; optimizer, included)
    normal_cost=objective_function(b.model)
    ζ=VariableRef[]
    if s["mode"]=="penalty"
        caps=r8_loss_caps(c)
        ζ=@variable(
            b.model,
            [i in eachindex(caps)],
            lower_bound=0,
            upper_bound=caps[i],
            base_name="worst_selected_loss_MWh"
        )
        # R9-RP2：同一事件多个故障是可选不确定实现，不能重复收取全部故障罚项。
        for w in b.recovery
            @constraint(b.model, ζ[w.pair.event]>=w.loss)
        end
        @objective(b.model, Min, normal_cost+s["penalty_MWh"]*sum(ζ))
    end
    types=[
        Dict("function"=>string(F), "set"=>string(S)) for
        (F, S) in list_of_constraint_types(b.model)
    ]
    all(
        F in (VariableRef, AffExpr) && S in (
            MOI.LessThan{Float64},
            MOI.GreaterThan{Float64},
            MOI.EqualTo{Float64},
            MOI.Interval{Float64},
            MOI.ZeroOne,
        ) for (F, S) in list_of_constraint_types(b.model)
    ) || error("灾前对照出现未声明的模型类型")
    (; b..., normal_cost, ζ, carrier, model_types = types)
end
