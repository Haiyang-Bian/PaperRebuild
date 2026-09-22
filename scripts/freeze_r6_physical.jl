using PaperRebuild, TOML, SHA

function r6_freeze_physical(path)
    VERSION==v"1.12.6" || error("Julia版本必须为1.12.6")
    ispath(path) && error("不能覆盖冻结物理模板")
    root=normpath(joinpath(@__DIR__, ".."))
    rulepath=joinpath(root, "configs", "r6", "physical-rule.toml")
    rule=TOML.parsefile(rulepath)
    rule["schema"]=="r6-physical-rule-v1" || error("构造规则版本错误")
    parentpath=joinpath(root, split(rule["parent"], '/')...)
    parent=load_r5_strategic_case(parentpath)
    T=rule["T"]
    T==24 && rule["dt_h"]==1.0 || error("该日模板规则显式限定24个一小时时段")
    dispatch=deepcopy(first(parent.data["risk"]["commitment"]["scenarios"])["case"])
    dispatch["T"], dispatch["dt_h"], dispatch["name"]=T, rule["dt_h"], rule["name"]
    dispatch["ambient_K"]=rule["ambient_K"]
    dispatch["electric"]["P_load_MW"]=[zeros(T), rule["load_MW"]]
    dispatch["electric"]["Q_load_Mvar"]=[zeros(T), fill(rule["reactive_load_Mvar"], T)]
    for a in dispatch["devices"]
        a["kind"]=="PV" && (a["available_MW"]=zeros(T))
    end
    for k in ("P_DA_MW", "R_up_MW", "R_down_MW", "energy_price", "up_price", "down_price")
        dispatch["award"][k]=zeros(T)
    end
    dispatch["realtime"]["alpha_up"]=zeros(T)
    dispatch["realtime"]["alpha_down"]=zeros(T)
    dispatch["realtime"]["price"]=rule["realtime_price_USD_MWh"]
    # 父边界均为常量，只扩展常量；禁止隐式重复四小时轨迹。
    function constant_day(v)
        all(==(first(v)), v) || error("非恒定父参数必须提供显式日轨迹")
        fill(first(v), T)
    end
    bounds=Dict(
        k=>Dict(side=>constant_day(v) for (side, v) in b) for
        (k, b) in parent.data["risk"]["commitment"]["bounds"]
    )
    bids=Dict(
        k=>Dict(side=>constant_day(v) for (side, v) in b) for (k, b) in parent.data["bid_bounds"]
    )
    market=deepcopy(parent.data["market"])
    market["T"], market["dt_h"], market["name"]=T, rule["dt_h"], rule["name"]
    market["description"]="Synthetic daily abundant-supply market; physical-rule.toml fixes hourly offers before optimization."
    market["load_MW"]=[constant_day(x) for x in market["load_MW"]]
    for k in ("reserve_up_MW", "reserve_down_MW")
        market[k]=constant_day(market[k])
    end
    for a in vcat(market["generators"], market["ies"])
        a["energy_bid"]=Float64.(rule["market_energy_bid_USD_MWh"])
        a["up_bid"]=fill(rule["market_up_bid_USD_MW_h"], T)
        a["down_bid"]=fill(rule["market_down_bid_USD_MW_h"], T)
    end
    c=R6PhysicalCase(
        Dict(
            "schema"=>"r6-physical-case-v1",
            "name"=>rule["name"],
            "origin"=>"synthetic",
            "dispatch"=>dispatch,
            "market"=>market,
            "bounds"=>bounds,
            "bid_bounds"=>bids,
            "leader_id"=>parent.data["leader_id"],
            "selection"=>parent.data["selection"],
            "temperature_domain"=>parent.data["risk"]["temperature_domain"],
            "provenance"=>Dict(
                "parent"=>rule["parent"],
                "parent_sha256"=>parent.sha256,
                "parent_file_sha256"=>bytes2hex(sha256(read(parentpath))),
                "rule"=>"configs/r6/physical-rule.toml",
                "rule_file_sha256"=>bytes2hex(sha256(read(rulepath))),
                "changes"=>rule["changes"],
                "hour_convention"=>rule["hour_convention"],
            ),
        ),
    )
    mkpath(dirname(abspath(path)))
    write(path, PaperRebuild.r5_market_text(c.data))
    load_r6_physical_case(path).sha256==c.sha256 || error("物理模板重读不一致")
    println("R6 physical template frozen: ", c.sha256, "; no optimization performed")
end

if abspath(PROGRAM_FILE)==(@__FILE__)
    length(ARGS)==1 || error("usage: freeze_r6_physical.jl <new-physical.toml>")
    r6_freeze_physical(ARGS[1])
end
