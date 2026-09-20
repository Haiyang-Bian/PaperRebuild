using PaperRebuild, TOML, CSV
include("r7_flow_planning_study.jl")

"""从原值逐水团重算散热与正常费用分项；不求解，不把恢复见证当失供最优解。"""
function lossy_energy_rows(report)
    items, _=joint_inputs(report)
    rows=NamedTuple[]
    for item in items
        rr=joint_frozen_read(joinpath(report, "records", item["id"]))
        r, q=rr.result, rr.validation
        q["robust_model_pass"]||continue
        d=rr.case.normal.data
        h, e=d["heat"], d["electric"]
        v=Dict(
            k=>PaperRebuild.r7_unpack(r["normal"]["values"], k) for k in keys(r["normal"]["values"])
        )
        f=PaperRebuild.r7_unpack(r["normal"]["flow_values"], "pipe")
        W, T=length(d["probabilities"]), d["periods"]
        weighted(a) = sum(d["probabilities"][w]*a[t, w] for t in axes(a, 1), w in 1:W)
        loss=zeros(T, W)
        delta=zeros(T, W)
        for (a, p) in enumerate(h["pipes"]), side in ("S", "R"), w in 1:W
            state=PaperRebuild.r7_normal_initial(d, p, side, w)
            for t in 1:T
                step=r7_pipe_step(
                    state;
                    mass_flow_kg_s = f[a, t],
                    inlet_K = v["τ_$side"][p[side=="S" ? "from" : "to"], t, w],
                    ambient_K = h["ambient_K"][t],
                    dt_h = d["dt_h"],
                    cp_J_kgK = h["c_J_kgK"],
                    UA_W_K = p["UA_$(side)_W_K"],
                    reference_K = h["$(side)_min_K"],
                )
                loss[t, w]+=step.loss_MWh
                before=r7_pipe_inventory(
                    state;
                    cp_J_kgK = h["c_J_kgK"],
                    reference_K = h["$(side)_min_K"],
                ).relative_heat_MWh
                after=r7_pipe_inventory(
                    step.state;
                    cp_J_kgK = h["c_J_kgK"],
                    reference_K = h["$(side)_min_K"],
                ).relative_heat_MWh
                delta[t, w]+=after-before
                state=step.state
            end
        end
        chp=only(i for (i, g) in enumerate(d["devices"]) if g["kind"]=="CHP")
        bes=only(i for (i, g) in enumerate(d["devices"]) if g["kind"]=="BES")
        length(d["devices"])==2||error("费用解析只适用于本批CHP与电池输入")
        gc, gb=d["devices"][chp], d["devices"][bes]
        gc["heat_ratio"]==gb["eta_ch"]==gb["eta_dis"]==1||error("解析前提改变")
        length(unique(e["price_USD_MWh"]))==1||error("平价解析前提改变")
        dt=d["dt_h"]
        heat_load=dt*sum(sum, h["load_MW"])
        electric_load=dt*sum(sum, e["load_MW"])
        heat=dt*weighted(v["H"][chp, :, :])
        generation=dt*weighted(v["P"][chp, :, :])
        purchase=dt*weighted(v["P_PCC"])
        throughput=dt*weighted(v["P_ch"][bes, :, :]+v["P_dis"][bes, :, :])
        storage_delta=sum(
            d["probabilities"][w]*(v["E_BES"][bes, end, w]-v["E_BES"][bes, 1, w]) for w in 1:W
        )
        start=q["normal_check"]["normal_validation"]["startup_cost_USD"]
        grid_price=first(e["price_USD_MWh"])
        base=grid_price*electric_load+(gc["cost_P_USD_MWh"]-grid_price)*heat_load
        loss_effect=(gc["cost_P_USD_MWh"]-grid_price)*weighted(loss)
        thermal_delta_effect=(gc["cost_P_USD_MWh"]-grid_price)*weighted(delta)
        battery_cost=gb["cost_P_USD_MWh"]*throughput
        identity=base+loss_effect+thermal_delta_effect+grid_price*storage_delta+battery_cost+start
        push!(
            rows,
            (
                id = item["id"],
                run_id = r["run_id"],
                UA_W_K = item["UA_W_K"],
                safety_group = item["safety_group"],
                control = item["control"],
                solver = item["solver"],
                heat_load_MWh = heat_load,
                electric_load_MWh = electric_load,
                normal_heat_MWh = heat,
                CHP_electric_MWh = generation,
                grid_purchase_MWh = purchase,
                normal_loss_MWh = weighted(loss),
                thermal_inventory_change_MWh = weighted(delta),
                battery_inventory_change_MWh = storage_delta,
                battery_throughput_MWh = throughput,
                base_cost_USD = base,
                loss_effect_USD = loss_effect,
                battery_cost_USD = battery_cost,
                startup_cost_USD = start,
                identity_cost_USD = identity,
                cost_USD = q["cost_USD"],
                cost_identity_residual_USD = abs(identity-q["cost_USD"]),
                heat_balance_residual_MWh = abs(heat-heat_load-weighted(loss)-weighted(delta)),
                electric_balance_residual_MWh = abs(
                    generation+purchase-electric_load-storage_delta,
                ),
                recovery_max_loss_MWh = maximum(
                    w["thermal"]["loss_to_environment_MWh"] for w in q["witness_checks"]
                ),
                elapsed_sec = r["elapsed_sec"],
                validation_sec = r["validation_sec"],
                budget_overrun_sec = r["budget_overrun_sec"],
            ),
        )
    end
    rows
end

function lossy_audit(report, dest)
    ispath(dest)&&error("不覆盖有损费用归因证据")
    joint_check(report)
    rows=lossy_energy_rows(report)
    mkpath(dest)
    CSV.write(joinpath(dest, "energy-cost.csv"), rows)
    cp(@__FILE__, joinpath(dest, "audit-source.jl"))
    write(
        joinpath(dest, "audit.toml"),
        PaperRebuild.r7_text(
            Dict(
                "schema"=>"r7-lossy-energy-audit-v1",
                "origin"=>"synthetic",
                "scope"=>"normal expected cost identity for frozen CHP and ideal battery case",
                "report_manifest_sha256"=>joint_hash(joinpath(report, "report-hashes.toml")),
                "files"=>joint_manifest(dest),
            ),
        ),
    )
    println("Lossy normal energy and cost identity saved for ", length(rows), " candidates.")
end

if abspath(PROGRAM_FILE)==@__FILE__
    length(ARGS)==2||error("usage: audit_r7_lossy_flow.jl REPORT NEW_AUDIT")
    lossy_audit(abspath.(ARGS)...)
end
