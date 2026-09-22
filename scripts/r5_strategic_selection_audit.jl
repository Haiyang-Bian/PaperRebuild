using PaperRebuild, CSV, TOML, SHA

function r5_strategic_selection_audit(dir)
    rules=TOML.parsefile(joinpath(@__DIR__, "..", "configs", "r5", "strategic", "study.toml"))
    rows=NamedTuple[]
    for e in rules["runs"]
        w=TOML.parsefile(joinpath(dir, "witnesses", e["id"]*".toml"))
        c=R5StrategicCase(w["case"])
        r=w["result"]
        haskey(r, "independent_market")||continue
        v=validate_r5_strategic(c, r)
        v["independent_market_kkt_pass"]||error("缺少独立出清认证，不能评价多解")
        chosen, independent=r["selected_market"], r["independent_market"]
        iv=v["independent_market"]
        tol=1e-6*(1+max(1.0, sum(g["p_max"] for g in c.data["market"]["generators"])))
        node=only(c.data["market"]["ies"])["node"]
        for t in 1:c.data["market"]["T"]
            selected=[only(chosen["values"][k])[t] for k in ("P_IES", "R_IES_up", "R_IES_down")]
            other=[only(independent["values"][k])[t] for k in ("P_IES", "R_IES_up", "R_IES_down")]
            push!(
                rows,
                (;
                    record_id = e["id"],
                    run_id = r["run_id"],
                    t,
                    selected_P_MW = selected[1],
                    selected_up_MW = selected[2],
                    selected_down_MW = selected[3],
                    independent_P_MW = other[1],
                    independent_up_MW = other[2],
                    independent_down_MW = other[3],
                    selected_energy_price = v["selected_market"]["LMP_USD_MWh"][node][t],
                    independent_energy_price = iv["LMP_USD_MWh"][node][t],
                    max_award_difference_MW = maximum(abs.(selected-other)),
                    award_tolerance_MW = tol,
                    same_awards_A1 = maximum(abs.(selected-other))<=tol,
                    lower_objective_difference = abs(
                        iv["clearing_objective"]-v["selected_market"]["clearing_objective"],
                    ),
                ),
            )
        end
    end
    rows
end

function r5_strategic_check_selection_audit(dir)
    meta=TOML.parsefile(joinpath(dir, "selection-audit.toml"))
    meta["solver_reexecuted"]==false && meta["script_sha256"]==bytes2hex(sha256(read(@__FILE__))) ||
        error("选择审计来源错误")
    rows=r5_strategic_selection_audit(dir)
    io=IOBuffer()
    CSV.write(io, rows)
    take!(io)==read(joinpath(dir, "selection-audit.csv"))||error("选择审计表不一致")
    length(rows)==meta["time_rows"] &&
    count(x->!x.same_awards_A1, rows)==meta["different_award_rows"] || error("多解统计不同")
    rows
end
