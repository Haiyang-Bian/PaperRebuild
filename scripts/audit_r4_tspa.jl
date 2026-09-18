# 只读定位两阶段失败；用全网热量守恒给出必要条件，不再运行求解器。
using PaperRebuild, TOML, CSV, SHA
length(ARGS) in (1, 2) || error("参数：study.toml [报告目录]")
study_path=abspath(ARGS[1])
study=TOML.parsefile(study_path)
dir=dirname(study_path)
checks=NamedTuple[]
solver_rows=NamedTuple[]
for entry in study["records"]
    loaded=read_r4_tspa_run(joinpath(dir, entry["id"]))
    c, r=loaded.case, loaded.result
    values=r["trading_selected"]["values"]
    d=c.data
    loss=sum(
        p["U_W_mK"]*p["length_m"]*(p["S_ref_K"]+p["R_ref_K"]-2p["ambient_K"])/1e6 for
        p in d["heat"]["pipes"]
    )
    for t in 1:d["T"]
        agnet=sum(
            d["actors"][i]["heat_ratio"]*values["P_CHP"][i][t]+d["actors"][i]["COP_HP"]*values["P_HP"][i][t]+d["actors"][i]["COP_EB"]*values["P_EB"][i][t]-values["H_D"][i][t]
            for i in 2:3
        )
        required_net=loss-agnet
        a=d["actors"][1]
        min_net=-(1+a["flex"])*a["H_load"][t]
        violation=max(min_net-required_net, 0.0)
        p23=d["heat"]["pipes"][2]
        loss23=p23["U_W_mK"]*p23["length_m"]*(p23["S_ref_K"]+p23["R_ref_K"]-2p23["ambient_K"])/1e6
        # 把A/B两个节点相加：来自DSO的管道出口热量=内部管损-两AG净供热。
        # 出口热量必须非负；负值独立证明当前固定方向/冻结控制模型不可行。
        required_incoming=loss23-agnet
        push!(
            checks,
            (
                run_id = entry["id"],
                t = t,
                loss_MW = loss,
                aggregator_net_MW = agnet,
                required_DSO_net_MW = required_net,
                minimum_DSO_net_MW = min_net,
                necessary_violation_MW = violation,
                required_H12_out_MW = required_incoming,
                cutset_violation_MW = max(-required_incoming, 0.0),
                A1_power_tolerance_MW = 1e-6*(1+d["electric"]["grid_max"]),
            ),
        )
    end
    strict=r["strict_network"]
    elastic=r["elastic_network"]
    for (stage, x) in (
        ("trading_solver", r["trading_solver"]),
        ("strict_network", strict),
        ("elastic_network", elastic),
    )
        push!(
            solver_rows,
            (
                run_id = entry["id"],
                stage = stage,
                status = x["status"],
                objective_type = x["objective_type"],
                solver_objective = get(x, "solver_objective", missing),
                objective_bound = get(x, "objective_bound", missing),
                relative_gap = get(x, "relative_gap", missing),
                cost_optimization_complete = x["cost_optimization_complete"],
            ),
        )
    end
    println(
        entry["id"],
        " | trading=",
        r["trading_solver"]["status"],
        " | selected=",
        r["selection"],
        " | gap=",
        get(r["trading_solver"], "relative_gap", "unavailable"),
        " | strict=",
        strict["status"],
        " | elastic=",
        elastic["status"],
    )
    if haskey(elastic["validation"], "physical_validation")
        bad=sort(
            filter(x->!x["pass"], elastic["validation"]["physical_validation"]["rows"]);
            by = x->-x["residual"]/x["tolerance"],
        )
        for x in first(bad, min(3, length(bad)))
            println(
                "  ",
                x["equation"],
                " node=",
                x["entity"],
                " t=",
                x["t"],
                " | ",
                x["residual"],
                " ",
                x["unit"],
            )
        end
    end
end
if length(ARGS)==1
    CSV.write(stdout, checks)
else
    output=ARGS[2]
    files=["network-necessary-condition.csv", "solver-evidence.csv", "audit.toml"]
    any(isfile(joinpath(output, f)) for f in files) && error("不覆盖原审计")
    mkpath(output)
    CSV.write(joinpath(output, files[1]), checks)
    CSV.write(joinpath(output, files[2]), solver_rows)
    write(
        joinpath(output, files[3]),
        PaperRebuild.r4_text(
            Dict(
                "batch"=>study["batch"],
                "script_sha256"=>bytes2hex(sha256(read(@__FILE__))),
                "study_sha256"=>bytes2hex(sha256(read(study_path))),
                "scope"=>"necessary heat balance conditions for frozen directed 1-2-3 network; not a full sufficiency proof",
            ),
        ),
    )
end
