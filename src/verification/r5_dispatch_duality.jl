const R5_DISPATCH_DUALITY_FILE = @__FILE__

# 独立按物理关联及累计质量区间组装Ax⪋b，不读取JuMP表达式或建模热核。
# 原始MOI乘子满足：>=行为正、<=行为负、等式自由；驻点为c-A'y=0。
function r5_dispatch_dual_system(c::R5DispatchCase)
    r5_dispatch_assert_case(c)
    d=c.data
    T, B, L, N, A, S, J, G=r5_dispatch_sizes(c)
    e, h, a, rt=d["electric"], d["heat"], d["award"], d["realtime"]
    ds, bs, ss, ps, ls=d["devices"], d["buildings"], h["sources"], h["pipes"], e["lines"]
    dt=d["dt_h"]
    cp=h["c_J_kgK"]/1e6
    sizes=Dict(
        "P_DER"=>G,
        "Q_DER"=>G,
        "P_PCC"=>1,
        "Q_PCC"=>1,
        "P_line"=>L,
        "Q_line"=>L,
        "v"=>B,
        "τ_S"=>N,
        "τ_R"=>N,
        "τ_src"=>S,
        "τ_load_R"=>J,
        "τ_pipe_S"=>A,
        "τ_pipe_R"=>A,
        "H_D"=>J,
        "P_DH"=>J,
        "τ_IN"=>J,
        "delivery"=>1,
        "mismatch"=>1,
    )
    key(k, i, t) = "$k/$i/$t"
    cost=Dict(key(k, i, t)=>0.0 for (k, n) in sizes for i in 1:n for t in 1:T)
    rows=Dict{String,Any}()
    function row(id, entity, t, sense, rhs, terms)
        idkey="$id/$entity/$t"
        haskey(rows, idkey)&&error("重复对偶行：$idkey")
        coef=Dict{String,Float64}()
        for (k, v) in terms
            coef[k]=get(coef, k, 0.0)+v
        end
        rows[idkey]=(coefficients = coef, sense = sense, rhs = Float64(rhs), bound = false)
    end
    function bounds(k, i, t, lo, hi)
        v=key(k, i, t)
        for (kind, value, sense) in (("lower", lo, :ge), ("upper", hi, :le))
            isfinite(value)||continue
            rows["$v/$kind"]=(
                coefficients = Dict(v=>1.0),
                sense = sense,
                rhs = Float64(value),
                bound = true,
            )
        end
    end
    for t in 1:T
        bounds("P_PCC", 1, t, e["pcc_min_MW"], e["pcc_max_MW"])
        bounds("Q_PCC", 1, t, e["qcc_min_Mvar"], e["qcc_max_Mvar"])
        bounds("mismatch", 1, t, 0, Inf)
        for n in 1:B
            bounds("v", n, t, e["v_min_pu"], e["v_max_pu"])
        end
        row("5-17", "root", t, :eq, e["v_ref_pu"], [key("v", e["root"], t)=>1.0])
        for (g, z) in enumerate(ds)
            bounds(
                "P_DER",
                g,
                t,
                z["p_min_MW"],
                z["kind"]=="PV" ? z["available_MW"][t] : z["p_max_MW"],
            )
            bounds("Q_DER", g, t, z["q_min_Mvar"], z["q_max_Mvar"])
            cost[key("P_DER", g, t)]=dt*z["cost_USD_MWh"]
            if z["kind"] in ("CHP", "GT")
                up=[key("P_DER", g, t)=>1.0]
                t>1&&push!(up, key("P_DER", g, t-1)=>-1.0)
                initial=t==1 ? z["P_initial_MW"] : 0.0
                row("5-10-up", z["id"], t, :le, dt*z["ramp_up_MW_h"]+initial, up)
                row(
                    "5-10-down",
                    z["id"],
                    t,
                    :le,
                    dt*z["ramp_down_MW_h"]-initial,
                    [k=>-v for (k, v) in up],
                )
            end
        end
        for n in 1:B
            p=Pair{String,Float64}[]
            q=Pair{String,Float64}[]
            n==e["root"]&&(push!(p, key("P_PCC", 1, t)=>1.0); push!(q, key("Q_PCC", 1, t)=>1.0))
            for (g, z) in enumerate(ds)
                z["node"]==n||continue
                push!(p, key("P_DER", g, t)=>(z["kind"]=="EB" ? -1.0 : 1.0))
                push!(q, key("Q_DER", g, t)=>1.0)
            end
            for (l, z) in enumerate(ls)
                sign=(z["to"]==n ? 1.0 : 0.0)-(z["from"]==n ? 1.0 : 0.0)
                push!(p, key("P_line", l, t)=>sign)
                push!(q, key("Q_line", l, t)=>sign)
            end
            for (j, z) in enumerate(bs)
                z["electric_node"]==n&&push!(p, key("P_DH", j, t)=>-1.0)
            end
            row("5-14", n, t, :eq, e["P_load_MW"][n][t], p)
            row("5-15", n, t, :eq, e["Q_load_Mvar"][n][t], q)
        end
        for (l, z) in enumerate(ls)
            bounds("P_line", l, t, -z["P_limit_MW"], z["P_limit_MW"])
            bounds("Q_line", l, t, -z["Q_limit_Mvar"], z["Q_limit_Mvar"])
            base=e["S_base_MVA"]*e["v_ref_pu"]
            row(
                "5-16",
                z["id"],
                t,
                :eq,
                0,
                [
                    key("v", z["to"], t)=>1.0,
                    key("v", z["from"], t)=>-1.0,
                    key("P_line", l, t)=>z["r_pu"]/base,
                    key("Q_line", l, t)=>z["x_pu"]/base,
                ],
            )
        end
        for n in 1:N
            bounds("τ_S", n, t, h["S_min_K"], h["S_max_K"])
            bounds("τ_R", n, t, h["R_min_K"], h["R_max_K"])
            ms=sum(z["m_kg_s"] for z in ps if z["from"]==n; init = 0.0)+sum(
                z["m_kg_s"] for z in bs if z["heat_node"]==n;
                init = 0.0,
            )
            mr=sum(z["m_kg_s"] for z in ps if z["to"]==n; init = 0.0)+sum(
                z["m_kg_s"] for z in ss if z["node"]==n;
                init = 0.0,
            )
            s=[key("τ_S", n, t)=>1.0]
            r=[key("τ_R", n, t)=>1.0]
            for (p, z) in enumerate(ps)
                z["to"]==n&&push!(s, key("τ_pipe_S", p, t)=>-z["m_kg_s"]/ms)
                z["from"]==n&&push!(r, key("τ_pipe_R", p, t)=>-z["m_kg_s"]/mr)
            end
            for (i, z) in enumerate(ss)
                z["node"]==n&&push!(s, key("τ_src", i, t)=>-z["m_kg_s"]/ms)
            end
            for (j, z) in enumerate(bs)
                z["heat_node"]==n&&push!(r, key("τ_load_R", j, t)=>-z["m_kg_s"]/mr)
            end
            row("5-20", n, t, :eq, 0, s)
            row("5-21", n, t, :eq, 0, r)
        end
        for (s, z) in enumerate(ss)
            bounds("τ_src", s, t, z["T_min_K"], z["T_max_K"])
            terms=[key("τ_src", s, t)=>-cp*z["m_kg_s"], key("τ_R", z["node"], t)=>cp*z["m_kg_s"]]
            for (g, dev) in enumerate(ds)
                dev["kind"] in ("CHP", "EB")&&dev["source_id"]==z["id"]&&push!(
                    terms,
                    key("P_DER", g, t)=>dev["heat_ratio"],
                )
            end
            row("5-18", z["id"], t, :eq, 0, terms)
        end
        for (j, z) in enumerate(bs)
            bounds("τ_load_R", j, t, z["R_min_K"], z["R_max_K"])
            bounds("τ_IN", j, t, z["T_min_K"], z["T_max_K"])
            bounds("H_D", j, t, 0, Inf)
            bounds("P_DH", j, t, 0, z["P_DH_max_MW"])
            row(
                "5-19",
                z["id"],
                t,
                :eq,
                0,
                [
                    key("H_D", j, t)=>1.0,
                    key("τ_S", z["heat_node"], t)=>-cp*z["m_kg_s"],
                    key("τ_load_R", j, t)=>cp*z["m_kg_s"],
                ],
            )
            η=dt/z["C_MWh_K"]
            U=dt*z["G_MW_K"]/z["C_MWh_K"]
            terms=[key("τ_IN", j, t)=>1+U, key("H_D", j, t)=>-η, key("P_DH", j, t)=>-η*z["COP_DH"]]
            t>1&&push!(terms, key("τ_IN", j, t-1)=>-1.0)
            row(
                "R5-D-building",
                z["id"],
                t,
                :eq,
                U*d["ambient_K"][t]+(t==1 ? z["T_initial_K"] : 0.0),
                terms,
            )
            t==T&&z["terminal_rule"]=="initial"&&row(
                "R5-D-terminal",
                z["id"],
                t,
                :eq,
                z["T_initial_K"],
                [key("τ_IN", j, t)=>1.0],
            )
        end
        row(
            "R5-D-delivery",
            "PCC",
            t,
            :eq,
            a["P_DA_MW"][t],
            [key("delivery", 1, t)=>1.0, key("P_PCC", 1, t)=>1.0],
        )
        request=rt["alpha_up"][t]*a["R_up_MW"][t]-rt["alpha_down"][t]*a["R_down_MW"][t]
        row(
            "5-3-plus",
            "PCC",
            t,
            :ge,
            request,
            [key("mismatch", 1, t)=>1.0, key("delivery", 1, t)=>1.0],
        )
        row(
            "5-3-minus",
            "PCC",
            t,
            :ge,
            -request,
            [key("mismatch", 1, t)=>1.0, key("delivery", 1, t)=>-1.0],
        )
        cost[key("delivery", 1, t)]=-dt*rt["price"][t]
        cost[key("mismatch", 1, t)]=dt*rt["penalty_USD_MWh"]
    end
    for (p, z) in enumerate(ps)
        delay=z["rho_kg_m3"]*z["area_m2"]*z["length_m"]/(z["m_kg_s"]*3600*dt)
        attenuation=exp(
            -z["loss_W_mK"]*3600*dt/(h["c_J_kgK"]*z["rho_kg_m3"]*z["area_m2"])*(
                ceil(Int, delay)-0.5
            ),
        )
        for side in ("S", "R"), t in 1:T
            node=side=="S" ? z["from"] : z["to"]
            terms=[key("τ_pipe_$side", p, t)=>1.0]
            rhs=(1-attenuation)*d["ambient_K"][t]
            left, right=t-1-delay, t-delay
            for k in floor(Int, left):ceil(Int, right)
                w=max(0.0, min(right, k)-max(left, k-1))
                w==0&&continue
                if k>0
                    push!(terms, key("τ_$side", node, k)=>-attenuation*w)
                else
                    rhs+=attenuation*w*z["history_$(side)_K"][end+k]
                end
            end
            row("5-25-26-$side", z["id"], t, :eq, rhs, terms)
        end
    end
    row(
        "5-4",
        "window",
        0,
        :le,
        rt["delta"]*dt*sum(a["R_up_MW"]+a["R_down_MW"]),
        [key("mismatch", 1, t)=>dt for t in 1:T],
    )
    constant=dt*sum(
        a["energy_price"] .* a["P_DA_MW"]-a["up_price"] .* a["R_up_MW"]-a["down_price"] .*
                                                                        a["R_down_MW"],
    )
    power_scale=max(
        1.0,
        e["pcc_max_MW"],
        sum(z["p_max_MW"] for z in ds; init = 0.0),
        sum(maximum(z) for z in e["P_load_MW"]),
    )
    price_scale=max(
        1.0,
        rt["penalty_USD_MWh"],
        maximum(abs.(rt["price"])),
        maximum(z["cost_USD_MWh"] for z in ds; init = 0.0),
    )
    money_scale=max(1.0, dt*price_scale*power_scale)
    scales=Dict(
        k=>(
            startswith(k, "τ_") ?
            max(h["S_max_K"], h["R_max_K"], maximum(z["T_max_K"] for z in bs; init = 1.0)) :
            startswith(k, "v/") ? e["v_max_pu"] : power_scale
        ) for k in keys(cost)
    )
    (; rows, cost, constant, sizes, scales, money_scale)
end

"""
    validate_r5_dispatch_duals(case, result)

独立按采用物理关系重建补救LP的Ax⪋b，检查保存的原始MOI对偶、所有上下界、互补与驻点。
费用和系数不读取JuMP对象；热输运按质量区间重叠重建，固定变量的双界均保留。
KKT采用冻结输入尺度及1e-6门槛，原对偶差用A2的1e-4；必须同时通过原有A1数值验算。
新增核验不改写旧运行或其历史判定；缺失对偶不返回可信梯度，线性模型通过不认证交流/水压。
"""
function validate_r5_dispatch_duals(c::R5DispatchCase, r)
    primal=validate_r5_dispatch(c, r)
    output=Dict{String,Any}(
        "schema"=>"r5-dispatch-kkt-v1",
        "case_sha256"=>c.sha256,
        "run_id"=>get(r, "run_id", ""),
        "kkt_pass"=>false,
        "dual_feasible"=>false,
        "rows"=>Dict{String,Any}[],
        "status"=>"missing_candidate",
        "model_pass"=>primal["model_pass"],
    )
    haskey(r, "values")||return output
    if haskey(primal, "invalid_values")
        output["status"]="invalid_values"
        return output
    end
    if !all(haskey(r, k) for k in ("raw_constraint_duals", "raw_bound_duals"))
        output["status"]="missing_duals"
        return output
    end
    sys=r5_dispatch_dual_system(c)
    expected=Set(k for (k, z) in sys.rows if !z.bound)
    boundkeys=Set(k for (k, z) in sys.rows if z.bound)
    if Set(keys(r["raw_constraint_duals"]))!=expected || Set(keys(r["raw_bound_duals"]))!=boundkeys
        output["status"]="dual_inventory_mismatch"
        return output
    end
    y=merge(Dict{String,Any}(r["raw_constraint_duals"]), Dict{String,Any}(r["raw_bound_duals"]))
    all(v->v isa Real&&isfinite(v), values(y))||(output["status"] = "nonfinite_dual"; return output)
    x=Dict(
        "$k/$i/$t"=>Float64(r["values"][k][i][t]) for (k, n) in sys.sizes for i in 1:n for
        t in 1:c.data["T"]
    )
    stationarity=copy(sys.cost)
    dual=sys.constant
    records=output["rows"]
    function record(id, kind, value, tol)
        value=abs(Float64(value))
        push!(
            records,
            Dict(
                "id"=>id,
                "kind"=>kind,
                "residual"=>value,
                "tolerance"=>tol,
                "normalized"=>value/tol,
                "pass"=>isfinite(value)&&value<=tol,
            ),
        )
    end
    for k in sort!(collect(keys(sys.rows)))
        z=sys.rows[k]
        mul=Float64(y[k])
        slack=sum(v*x[j] for (j, v) in z.coefficients)-z.rhs
        row_scale=max(1.0, abs(z.rhs), sum(abs(v)*sys.scales[j] for (j, v) in z.coefficients))
        sign_error=z.sense==:ge ? max(0.0, -mul) : z.sense==:le ? max(0.0, mul) : 0.0
        record(k, "sign", sign_error*row_scale/sys.money_scale, 1e-6)
        record(k, "complementarity", mul*slack/sys.money_scale, 1e-6)
        for (j, v) in z.coefficients
            stationarity[j]-=v*mul
        end
        dual+=z.rhs*mul
    end
    for k in sort!(collect(keys(stationarity)))
        record(k, "stationarity", stationarity[k]*sys.scales[k]/sys.money_scale, 1e-6)
    end
    objective=sys.constant+sum(sys.cost[k]*x[k] for k in keys(x))
    record(
        "independent-objective",
        "objective",
        (objective-primal["operating_net_cost"])/max(1, abs(objective)),
        1e-6,
    )
    gap=abs(objective-dual)/max(1.0, abs(objective), abs(dual))
    record("primal-dual-gap", "gap", gap, 1e-4)
    recourse_gap=abs(objective-dual)/max(1.0, abs(objective-sys.constant), abs(dual-sys.constant))
    record("recourse-primal-dual-gap", "gap", recourse_gap, 1e-4)
    output["dual_feasible"]=all(z["pass"] for z in records if z["kind"] in ("sign", "stationarity"))
    output["kkt_pass"]=primal["model_pass"]&&primal["cost_pass"]&&primal["auxiliary_exact_pass"]&&all(
        z["pass"] for z in records
    )
    merge!(
        output,
        Dict(
            "status"=>"evaluated",
            "primal_objective"=>objective,
            "dual_objective"=>dual,
            "day_ahead_cost"=>sys.constant,
            "relative_gap"=>gap,
            "recourse_relative_gap"=>recourse_gap,
            "money_scale_USD"=>sys.money_scale,
            "stationarity_raw"=>stationarity,
            "raw_multipliers_unchanged"=>true,
            "certificate_scope"=>"Numerical LP KKT under frozen tolerances; not exact-arithmetic global certification",
        ),
    )
    output
end

"""
    r5_dispatch_sensitivity(case, result; objective=:recourse)

仅从通过独立KKT的补救LP返回对日前购电/上下备用(MW)的次梯度，单位为USD/MW且已含dt。
分解贡献来自交付等式、绝对误差双行、容量分母预算和日前费用常数；objective可选total或recourse。
保持价格、设备、历史和调用轨迹不变；退化最优解返回一个次梯度，不宣称处处可微或唯一。
缺失/不可信对偶时gradient为空，不能用于割；仅属于固定舒适分支。
"""
function r5_dispatch_sensitivity(c::R5DispatchCase, r; objective = :recourse)
    objective in (:recourse, :total)||error("灵敏度费用口径必须为recourse或total")
    kkt=validate_r5_dispatch_duals(c, r)
    out=Dict{String,Any}(
        "schema"=>"r5-dispatch-sensitivity-v1",
        "case_sha256"=>c.sha256,
        "run_id"=>get(r, "run_id", ""),
        "trusted"=>kkt["kkt_pass"],
        "kkt"=>kkt,
        "objective_type"=>string(objective),
        "gradient"=>Dict{String,Any}(),
        "units"=>"USD/MW",
    )
    kkt["kkt_pass"]||return out
    d=c.data
    dt=d["dt_h"]
    a=d["award"]
    rt=d["realtime"]
    y=r["raw_constraint_duals"]
    delivery=[y["R5-D-delivery/PCC/$t"] for t in 1:d["T"]]
    mismatch=[y["5-3-plus/PCC/$t"]-y["5-3-minus/PCC/$t"] for t in 1:d["T"]]
    budget=fill(dt*rt["delta"]*y["5-4/window/0"], d["T"])
    gradient=Dict(
        "P_DA_MW"=>delivery,
        "R_up_MW"=>rt["alpha_up"] .* mismatch+budget,
        "R_down_MW"=>-rt["alpha_down"] .* mismatch+budget,
    )
    da=Dict(
        "P_DA_MW"=>dt*a["energy_price"],
        "R_up_MW"=>-dt*a["up_price"],
        "R_down_MW"=>-dt*a["down_price"],
    )
    objective==:total&&foreach(k->(gradient[k]=gradient[k]+da[k]), keys(gradient))
    out["gradient"]=gradient
    out["contributions"]=Dict(
        "delivery"=>delivery,
        "mismatch"=>mismatch,
        "capacity_budget"=>budget,
        "day_ahead"=>da,
    )
    out["kind"]="LP_subgradient_fixed_comfort_branch"
    out["value"]=kkt["primal_objective"]-(objective==:recourse ? kkt["day_ahead_cost"] : 0.0)
    out
end
