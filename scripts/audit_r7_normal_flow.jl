using TOML, SHA
include("r7_normal_flow_study.jl")
length(ARGS)==2 || error("usage: audit_r7_normal_flow.jl REPORT NEW_AUDIT")
src, dest=abspath.(ARGS);
ispath(dest)&&error("不覆盖连续流量费用审计")
items, rule=flow_inputs(src);
records=Dict{String,Any}[]
for group in rule["groups"]
    fixed=only(
        filter(x->x["group"]==group&&x["control"]=="prescribed"&&x["solver"]=="HiGHS", items),
    )
    free=only(filter(x->x["group"]==group&&x["control"]=="continuous", items))
    a=flow_read(joinpath(src, "records", fixed["id"]))
    c=a.case
    d=c.data
    ds=d["devices"]
    h=d["heat"]
    record=Dict{String,Any}(
        "group"=>group,
        "case_sha256"=>c.sha256,
        "fixed_run_id"=>a.result["run_id"],
        "fixed_record_sha256"=>PaperRebuild.r7_digest(a.result),
        "status"=>"not_applicable",
        "bound_kind"=>"analytic_conservation_not_solver_bound",
    )
    hypotheses=Dict(
        "constant_price"=>all(
            ==(first(d["electric"]["price_USD_MWh"])),
            d["electric"]["price_USD_MWh"],
        ),
        "single_chp_and_batteries"=>count(z->z["kind"]=="CHP", ds)==1&&all(
            z->z["kind"] in ("CHP", "BES"),
            ds,
        ),
        "ideal_batteries"=>all(z["eta_ch"]==z["eta_dis"]==1 for z in ds if z["kind"]=="BES"),
        "periodic_pipe_inventory"=>d["heat_terminal_rule"]=="pipe_inventory_initial",
        "zero_heat_loss"=>all(p["UA_$(side)_W_K"]==0 for p in h["pipes"] for side in ("S", "R")),
        "same_input"=>fixed["case_sha256"]==free["case_sha256"],
    )
    record["hypotheses"]=hypotheses
    if all(values(hypotheses))
        for kind in ("pipe", "source", "load")
            f=PaperRebuild.r7_unpack(fixed["spec"], kind*"_min")
            all(
                PaperRebuild.r7_unpack(free["spec"], kind*"_min") .<=
                f .<=
                PaperRebuild.r7_unpack(free["spec"], kind*"_max"),
            ) || error("固定域未嵌入连续域")
        end
        chp=only(filter(z->z["kind"]=="CHP", ds))
        λ=first(d["electric"]["price_USD_MWh"])
        Le=d["dt_h"]*sum(sum(row) for row in d["electric"]["load_MW"])
        Lh=d["dt_h"]*sum(sum(row) for row in h["load_MW"])
        bound=λ*Le+(chp["cost_P_USD_MWh"]-λ)*Lh/chp["heat_ratio"]
        record["analytic_lower_bound_USD"]=bound
        record["electric_load_MWh"]=Le
        record["heat_load_MWh"]=Lh
        record["fixed_candidate_pass"]=a.result["candidate_accepted"]
        if a.result["candidate_accepted"]
            cost=a.validation["cost_USD"]
            gap=(cost-bound)/max(1, abs(cost))
            record["feasible_upper_bound_USD"]=cost
            record["relative_gap"]=gap
            record["status"]=-1e-6<=gap<=1e-4 ?
                             "declared_continuous_domain_closed_by_embedding_A2" :
                             "analytic_bound_not_attained"
        else
            record["status"]="analytic_bound_without_valid_witness"
        end
    end
    push!(records, record)
end
mkpath(dest)
write(
    joinpath(dest, "audit.toml"),
    PaperRebuild.r7_text(
        Dict(
            "schema"=>"r7-normal-flow-cost-audit-v1",
            "origin"=>"synthetic",
            "records"=>records,
            "formula"=>"price * electric_load + (chp_cost - price) * heat_load / heat_ratio",
            "proof"=>"periodic lossless heat fixes CHP total; ideal cyclic BES has zero net energy; startup and throughput costs are nonnegative",
            "scope"=>"same declared positive lossless normal domain, no disaster or original full-domain claim",
        ),
    ),
)
cp(joinpath(src, "inputs.toml"), joinpath(dest, "inputs.toml"));
cp(@__FILE__, joinpath(dest, "audit-source.jl"))
write(joinpath(dest, "files.toml"), PaperRebuild.r7_text(Dict("files"=>flow_manifest(dest))))
for r in records
    println(
        r["group"],
        " ",
        r["status"],
        " bound=",
        get(r, "analytic_lower_bound_USD", "not_applicable"),
    )
end
