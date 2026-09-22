using PaperRebuild, TOML, CSV, SHA

"""以保存的出清量和原始乘子重算支付；不以存档的通过标志代替验算。"""
function r5_market_payment_tables(witnesses)
    summary=NamedTuple[]
    components=NamedTuple[]
    periods=NamedTuple[]
    for w in witnesses
        c=R5MarketCase(w["case"])
        r=w["result"]
        c.sha256==r["case_sha256"]||error("支付输入身份错误")
        bytes2hex(sha256(PaperRebuild.r5_market_text(r)))==w["result_content_sha256"]||error(
            "市场原值改变",
        )
        p=r5_market_payment_identity(c, r)
        p==w["payment"]||error("支付验算改变")
        id=w["record_id"]
        push!(
            summary,
            (;
                record_id = id,
                run_id = r["run_id"],
                case_name = c.data["name"],
                case_sha256 = c.sha256,
                solver_status = r["status"],
                payment_status = p["status"],
                model_pass = p["market_model_pass"],
                kkt_pass = p["market_kkt_pass"],
                identity_pass = p["identity_pass"],
                valid = p["valid_for_reformulation"],
                direct_USD = get(p, "direct_payment_USD", NaN),
                affine_USD = get(p, "affine_payment_USD", NaN),
                residual_USD = get(p, "identity_residual_USD", NaN),
                tolerance_USD = get(p, "identity_tolerance_USD", NaN),
            ),
        )
        for k in sort!(collect(keys(get(p, "linear_terms_USD", Dict()))))
            push!(
                components,
                (;
                    record_id = id,
                    run_id = r["run_id"],
                    component = k,
                    value_USD = p["linear_terms_USD"][k],
                ),
            )
        end
        for (i, row) in enumerate(get(p, "payment_by_IES_USD", [])), t in eachindex(row)
            push!(
                periods,
                (;
                    record_id = id,
                    run_id = r["run_id"],
                    IES = c.data["ies"][i]["id"],
                    t,
                    payment_USD = row[t],
                ),
            )
        end
    end
    Dict("comparison.csv"=>summary, "components.csv"=>components, "payments.csv"=>periods)
end
