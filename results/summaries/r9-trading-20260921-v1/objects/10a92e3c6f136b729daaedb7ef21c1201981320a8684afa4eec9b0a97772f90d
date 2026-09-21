# 从保存的原始乘子、当前局部仿射/锥表达式及原始变量重算KKT。
# 不相信已保存的trusted布尔值；也不读取求解器或再次求解。
function r3_local_kkt_witness(model, values, kkt)
    vars=all_variables(model)
    length(vars)==length(values) || return false
    x=Dict(zip(vars, values))
    f0=objective_function(model)
    f0 isa AffExpr || return false
    station=Dict(v=>coefficient(f0, v) for v in vars)
    denom=Dict(v=>1+abs(station[v]) for v in vars)
    dualobj=constant(f0)
    index=0
    primal=0.0
    dualerror=0.0
    comp=0.0
    nrm(x) = sqrt(sum(abs2, x))
    socerr(x) = max(0.0, nrm(x[2:end])-x[1])
    for (F, S) in list_of_constraint_types(model), cr in all_constraints(model, F, S)
        index+=1
        index<=length(kkt["rows"]) || return false
        obj=constraint_object(cr)
        f, set=obj.func, obj.set
        fs=f isa AbstractVector ? f : [f]
        y=kkt["rows"][index]["raw_dual"]
        length(fs)==length(y) || return false
        z=[value(v->x[v], a) for a in fs]
        offsets=Float64[]
        for (a, yi) in zip(fs, y)
            if a isa VariableRef
                station[a]-=yi
                denom[a]+=abs(yi)
                push!(offsets, 0.0)
            elseif a isa AffExpr
                push!(offsets, constant(a))
                for (coef, v) in linear_terms(a)
                    station[v]-=yi*coef
                    denom[v]+=abs(yi*coef)
                end
            else
                return false
            end
        end
        if set isa MOI.EqualTo
            slack=z .- set.value
            offsets .-= set.value
            pe=abs(slack[1])
            de=0.0
        elseif set isa MOI.LessThan
            slack=z .- set.upper
            offsets .-= set.upper
            pe=max(0.0, slack[1])
            de=max(0.0, y[1])
        elseif set isa MOI.GreaterThan
            slack=z .- set.lower
            offsets .-= set.lower
            pe=max(0.0, -slack[1])
            de=max(0.0, -y[1])
        elseif set isa MOI.SecondOrderCone
            slack=z
            pe=socerr(z)
            de=socerr(y)
        else
            return false
        end
        primal=max(primal, pe/max(1, nrm(z), nrm(slack)))
        dualerror=max(dualerror, de/max(1, nrm(y)))
        comp=max(comp, abs(sum(slack .* y))/max(1, nrm(slack)*nrm(y)))
        dualobj-=sum(offsets .* y)
    end
    index==length(kkt["rows"]) || return false
    stat=maximum(abs(station[v])/denom[v] for v in vars; init = 0.0)
    obj=value(v->x[v], f0)
    return max(primal, dualerror, comp, stat)<=1e-6 && abs(obj-dualobj)/max(1, abs(obj))<=1e-4
end
