module R9GurobiStart
using JuMP, Gurobi

"""向已完成建模的Gurobi模型批量写入完整初值，并逐值读回；LP与MIP采用各自原生属性。"""
function set_native_start!(model, values; lp::Bool)
    vars=all_variables(model)
    length(values)==length(vars) && all(isfinite, values) || error("完整初值维度/数值错误")
    lp && any(is_binary, vars) && error("含二元变量不能使用LP初值属性")
    MOI.Utilities.attach_optimizer(backend(model))
    native=unsafe_backend(model)
    native isa Gurobi.Optimizer || error("原生初值接口只支持Gurobi")
    Gurobi.GRBupdatemodel(native)==0 || error("Gurobi模型更新失败")
    n=length(vars)
    columns=[Int(Gurobi.c_column(native, optimizer_index(v)))+1 for v in vars]
    sort(columns)==collect(1:n) || error("原生列映射不完整或存在额外变量")
    raw=fill(NaN, n)
    for (i, j) in enumerate(columns)
        raw[j]=values[i]
    end
    # PStart是连续LP的原始起点；Start是MIP可行候选，二者不能互换。
    attr=lp ? "PStart" : "Start"
    Gurobi.GRBsetdblattrarray(native, attr, 0, n, raw)==0 || error("写入原生初值失败")
    Gurobi.GRBupdatemodel(native)==0 || error("Gurobi初值更新失败")
    observed=similar(raw)
    Gurobi.GRBgetdblattrarray(native, attr, 0, n, observed)==0 || error("读回原生初值失败")
    isequal(raw, observed) || error("原生初值读回不一致")
    Dict(
        "attribute"=>attr,
        "variables"=>n,
        "exact_readback"=>true,
        "constraints_or_objective_changed"=>false,
        "scope"=>"initial_point_only_no_optimality_claim",
    )
end
end
