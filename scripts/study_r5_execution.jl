include("r5_risk_setup.jl")
length(ARGS)==1 || error("参数：新执行批次ID")
root=normpath(joinpath(@__DIR__, ".."))
id=only(ARGS)
occursin(r"^[A-Za-z0-9_-]+$", id) || error("批次ID错误")
dir=joinpath(root, "results", "runs", id)
ispath(dir) && error("不覆盖执行批次")
rulepath=joinpath(root, "configs", "r5", "execution", "study.toml")
rules=TOML.parsefile(rulepath)
bytes2hex(sha256(read(joinpath(@__DIR__, "freeze_r5_execution.jl"))))==rules["fixture_sha256"] ||
    error("执行构造规则改变")
for e in rules["runs"]
    rel=get(e, "parent", get(e, "input", ""))
    hash=get(e, "parent_sha256", get(e, "input_sha256", ""))
    bytes2hex(sha256(read(joinpath(root, split(rel, '/')...))))==hash || error("冻结父输入改变")
end
highs=r5_risk_optimizer(:highs)
clarabel=r5_risk_optimizer(:clarabel)
spec=PaperRebuild.r5_execution_spec(rules["spec"])
mkpath(dir)
study=Dict{String,Any}(
    "schema"=>"r5-execution-study-v1",
    "batch_id"=>id,
    "rules"=>rules,
    "config_sha256"=>bytes2hex(sha256(read(rulepath))),
    "source_commit"=>readchomp(Cmd(["git", "-C", root, "rev-parse", "HEAD"])),
    "source_sha256"=>PaperRebuild.r5_execution_science_hashes(),
    "complete"=>false,
    "records"=>Dict{String,Any}[],
)
save() = write(joinpath(dir, "study.toml"), PaperRebuild.r5_market_text(study))
save()
for e in rules["runs"]
    start=time()
    deadline=start+rules["budget_sec"]
    record=merge(
        deepcopy(e),
        Dict{String,Any}("stages"=>String[], "stage_sha256"=>Dict{String,String}()),
    )
    println("START ", e["id"])
    flush(stdout)
    out=joinpath(dir, e["id"])
    mkpath(out)
    if e["mode"]=="market_only"
        mc=load_r5_market_case(joinpath(root, split(e["input"], '/')...))
        c=nothing
        parent=nothing
    else
        w=TOML.parsefile(joinpath(root, split(e["parent"], '/')...))
        c=R5StrategicCase(w["case"])
        c.sha256==e["case_sha256"] || error("父案例规范化哈希变化")
        parent=w["result"]
        bids=e["mode"]=="preset_minimum_norm" ?
             Dict(k=>(b["lower"] .+ b["upper"]) ./ 2 for (k, b) in c.data["bid_bounds"]) :
             parent["bids"]
        mc=PaperRebuild.r5_strategic_market_case(c, bids)
    end
    market=nothing
    if time()>=deadline
        record["selection_pass"]=false
        record["selection_status"]="budget_exhausted_before_selection"
    elseif e["mode"] in ("market_only", "minimum_norm", "preset_minimum_norm")
        r=solve_r5_market_execution(
            mc;
            lp_optimizer = highs,
            qp_optimizer = clarabel,
            spec,
            budget_sec = min(rules["selection_budget_sec"], deadline-time()),
        )
        save_r5_execution_run(
            Dict("kind"=>"market_execution", "case"=>mc.data),
            r,
            joinpath(out, "selection"),
        )
        push!(record["stages"], "selection")
        record["selection_pass"]=r["validation"]["execution_pass"]
        record["selection_status"]=r["status"]
        r["validation"]["execution_pass"] && (market=r["market"])
    else
        market=parent[e["mode"]=="saved_selected" ? "selected_market" : "independent_market"]
        record["selection_pass"]=true
        record["selection_status"]="preserved_parent_market_witness"
    end
    if c!==nothing && market!==nothing && time()<deadline
        d=evaluate_r5_execution_delivery(
            c,
            mc,
            market;
            optimizer = highs,
            oracle_optimizer = highs,
            budget_sec = deadline-time(),
        )
        payload=Dict(
            "kind"=>"fixed_award_delivery",
            "case"=>c.data,
            "market_case"=>mc.data,
            "market"=>market,
        )
        save_r5_execution_run(payload, d, joinpath(out, "delivery"))
        push!(record["stages"], "delivery")
        record["delivery_status"]=d["status"]
        record["delivery_pass"]=d["validation"]["delivery_pass"]
        record["cost_complete"]=d["validation"]["cost_complete"]
        haskey(d["validation"], "total_cost_USD") &&
            (record["total_cost_USD"]=d["validation"]["total_cost_USD"])
    elseif c!==nothing
        record["delivery_status"]=market===nothing ? "uncertified_market_selection" :
                                  "budget_exhausted"
        record["delivery_pass"]=false
        record["cost_complete"]=false
    end
    record["elapsed_sec"]=time()-start
    for stage in record["stages"]
        record["stage_sha256"][stage]=bytes2hex(sha256(read(joinpath(out, stage, "result.toml"))))
    end
    write(joinpath(dir, e["id"], "record.toml"), PaperRebuild.r5_market_text(record))
    push!(study["records"], record)
    save()
    println(
        "END ",
        e["id"],
        " selection=",
        record["selection_pass"],
        " delivery=",
        get(record, "delivery_status", "not_applicable"),
        " pass=",
        get(record, "delivery_pass", false),
        " cost=",
        get(record, "total_cost_USD", NaN),
    )
    flush(stdout)
end
study["complete"]=true
save()
println("Execution study complete; all outcomes retained.")
