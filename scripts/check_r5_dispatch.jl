using PaperRebuild, TOML, CSV
include("r5_dispatch_docs.jl")
"--sync" in ARGS && sync_r5_dispatch_docs()
root=normpath(joinpath(@__DIR__, ".."))
d=TOML.parsefile(joinpath(root, "docs", "reading", "ch05", "dispatch.toml"))
Set(x["id"] for x in d["equation"])==Set("5-$i" for i in 1:31) || error("原式范围不完整")
length(d["equation"])==31 && length(d["symbol"])==12 && length(d["issue"])==6 ||
    error("台账范围改变")
page=read(joinpath(root, "docs", "src", "ch05-dispatch-equations.md"), String)
api=read(joinpath(root, "docs", "src", "api.md"), String)
tests=read(joinpath(root, "test", "r5_dispatch.jl"), String)
for x in d["equation"]
    occursin("\\tag{"*x["id"]*"}", page)&&!isempty(x["adopted"]) || error("原式或解释缺失")
end
for category in ("symbol", "issue")
    ids=[x["id"] for x in d[category]]
    length(unique(ids))==length(ids)||error("重复ID")
end
for x in d["symbol"],
    k in ("latex", "meaning", "category", "unit", "julia", "dimensions", "domain", "source")

    !isempty(strip(x[k]))||error("符号缺失字段")
end
for name in (
    "r5_building_coefficients",
    "r5_building_temperature",
    "R5DispatchCase",
    "load_r5_dispatch_case",
    "r5_award_from_market",
    "build_r5_dispatch",
    "solve_r5_dispatch",
    "validate_r5_dispatch",
    "save_r5_dispatch_run",
    "read_r5_dispatch_run",
)
    Base.Docs.hasdoc(PaperRebuild, Symbol(name)) && occursin("PaperRebuild."*name, api) ||
        error("API/docstring缺失")
end
occursin(d["test"], tests)||error("测试关联缺失")
config=joinpath(root, "configs", "r5", "dispatch", "study.toml")
rules=TOML.parsefile(config)
length(rules["input_sha256"])==11 && length(rules["records"])==24 || error("正式输入范围变化")
length(unique(x["id"] for x in rules["records"]))==24 || error("运行ID重复")
marketdir=joinpath(root, "results", "summaries", "r5-market-verified")
marketmeta=TOML.parsefile(joinpath(marketdir, "report.toml"))
marketvalues=collect(CSV.File(joinpath(marketdir, "dispatch.csv")))
marketprices=collect(CSV.File(joinpath(marketdir, "prices.csv")))
for (name, hash) in rules["input_sha256"]
    c=load_r5_dispatch_case(joinpath(dirname(config), name*".toml"))
    c.sha256==hash || error("冻结输入变化：$name")
    award=c.data["award"]
    if award["origin"]=="verified_market"
        award["parent_result_sha256"]==marketmeta["raw_source_hashes"]["two_bus--highs"] ||
            error("市场来源原值不同")
        rows=sort(
            filter(
                x->x.record_id=="two_bus--highs"&&x.kind=="ies"&&x.actor==award["ies_id"],
                marketvalues,
            );
            by = x->x.t,
        )
        length(rows)==c.data["T"] && all(x.run_id==award["parent_run_id"] for x in rows) ||
            error("市场成交来源不同")
        for (key, field) in (("P_DA_MW", :P_MW), ("R_up_MW", :up_MW), ("R_down_MW", :down_MW))
            all(
                isapprox(award[key][i], getproperty(x, field); atol = 1e-12, rtol = 1e-12) for
                (i, x) in enumerate(rows)
            ) || error("中标量被更改")
        end
        prices=sort(filter(x->x.record_id=="two_bus--highs"&&x.node==2, marketprices); by = x->x.t)
        all(
            isapprox(award["energy_price"][i], x.LMP_USD_MWh; atol = 1e-12) for
            (i, x) in enumerate(prices)
        )||error("节点电价不同")
    end
end
println("R5 dispatch: 31 original equations, 12 symbol groups and 6 adoption boundaries mapped.")
