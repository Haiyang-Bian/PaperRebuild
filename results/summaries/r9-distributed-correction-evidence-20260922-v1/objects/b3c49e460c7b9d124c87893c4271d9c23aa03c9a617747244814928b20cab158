const R9_EVALUATION_REPORT_FILE = @__FILE__

function r9_evaluation_science_paths()
    paths = r6_evaluation_science_paths()
    root = normpath(joinpath(dirname(R9_EVALUATION_CORE_FILE), "..", ".."))
    for file in (R9_EVALUATION_CORE_FILE, R9_EVALUATION_SOLVE_FILE, R9_EVALUATION_REPORT_FILE)
        paths[replace(relpath(file, root), '\\'=>'/')] = file
    end
    paths["src/verification/r6_statistics.jl"] = joinpath(root, "src/verification/r6_statistics.jl")
    paths
end

"""
    summarize_r9_reserve_days(ids, validations; currency, epsilon=0.05, confidence=0.95)

R9-OS4：以完整新日为样本，汇总实际舒适事件和缺失费用；未知全部计入风险上界。
未完成日不得进入总体均费，仍可报告已完成日的条件费用分布。币种显式传入，不能将CNY字段标为USD。
该统计只适用于冻结采样分布及完整未来补救，不能继承训练有限支持保证或解释为在线运行可靠性。
"""
function summarize_r9_reserve_days(ids, vals; currency, epsilon = 0.05, confidence = 0.95)
    length(ids)==length(vals)>0 && length(unique(ids))==length(ids) || error("完整日身份错误")
    currency in ("CNY", "USD") && all(v["currency"]==currency for v in vals) || error("混合币种")
    costs=Float64[]
    events=Symbol[]
    for v in vals
        event=Symbol(v["comfort_outcome"])
        complete=v["cost_complete"]
        complete == (event != :unknown) || error("费用完成与操作事件不符")
        if complete
            v["model_pass"] && v["kkt_pass"] && isfinite(v["operating_net_cost"]) ||
                error("未核查的完成日")
            push!(costs, v["operating_net_cost"])
        end
        push!(events, event)
    end
    n=length(ids)
    Dict(
        "schema"=>"r9-reserve-days-summary-v1",
        "currency"=>currency,
        "n"=>n,
        "ids_sha256"=>r9_evaluation_hash(Dict("ids"=>String.(ids))),
        "risk"=>r6_risk_evidence(events; epsilon, confidence),
        "complete_cost_days"=>length(costs),
        "missing_cost_days"=>n-length(costs),
        "all_costs_complete"=>length(costs)==n,
        "mean_operating_net_cost"=>length(costs)==n ? sum(costs)/n : NaN,
        "observed_mean_operating_net_cost"=>isempty(costs) ? NaN : sum(costs)/length(costs),
        "observed_cost_quantiles"=>isempty(costs) ? Dict{String,Float64}() :
                                   Dict(
            "q05"=>r6_quantile(costs, 0.05),
            "q50"=>r6_quantile(costs, 0.5),
            "q95"=>r6_quantile(costs, 0.95),
        ),
        "scope"=>"frozen_synthetic_distribution_complete_future_recourse",
    )
end
r9_evaluation_science_hashes() =
    Dict(k=>bytes2hex(sha256(read(v))) for (k, v) in r9_evaluation_science_paths())

# 完整原变量与乘子始终保存；可重建的数万条残差只保存分组计数和极值，避免每日报告超过5 MiB。
function r9_compact_day_validation(x::AbstractDict)
    out = Dict{String,Any}()
    for (key, value) in x
        if key == "rows" && value isa AbstractVector
            groups = Dict{String,Any}()
            for row in value
                id = get(row, "group", get(row, "kind", "unclassified"))*"/"*get(row, "unit", "1")
                g = get!(
                    groups,
                    id,
                    Dict{String,Any}("count"=>0, "failed"=>0, "max_normalized"=>0.0),
                )
                g["count"] += 1
                g["failed"] += !row["pass"]
                g["max_normalized"] = max(g["max_normalized"], row["normalized"])
            end
            out["row_count"] = length(value)
            out["row_groups"] = groups
        elseif key != "stationarity_raw"
            out[key] = value isa AbstractDict ? r9_compact_day_validation(value) : value
        end
    end
    out
end

"""
    save_r9_reserve_day(policy, trajectory, result, directory)

原子保存单日策略、轨迹、完整原始变量/对偶和核验结果；拒绝覆盖、源码漂移或伪造摘要。
逐日不复制整套源码，正式批次必须另冻结公共依赖闭包。read_r9_reserve_day会拒绝用变更的依赖静默重判旧结果。
"""
function save_r9_reserve_day(p::R9ReservePolicy, x::AbstractMatrix, r, directory::AbstractString)
    v = validate_r9_reserve_day(p, x, r)
    r5_risk_validation_text(r9_compact_day_validation(v)) ==
    r5_risk_validation_text(r["validation"]) || error("逐日摘要不符")
    r["source_hashes_at_solve"] == r9_evaluation_science_hashes() || error("保存前依赖改变")
    dest = abspath(directory)
    ispath(dest) && error("不覆盖既有日记录")
    mkpath(dirname(dest))
    staging = mktempdir(dirname(dest); prefix = basename(dest)*".writing-")
    for (name, value) in (
        ("policy.toml", p.data),
        ("trajectory.toml", Dict("values"=>r5_market_rows(x))),
        ("result.toml", r),
    )
        write(joinpath(staging, name), r5_market_text(value))
    end
    hashes = Dict(
        name=>bytes2hex(sha256(read(joinpath(staging, name)))) for
        name in ("policy.toml", "trajectory.toml", "result.toml")
    )
    write(
        joinpath(staging, "files.toml"),
        r5_market_text(Dict("schema"=>"r9-reserve-day-artifact-v1", "files"=>hashes)),
    )
    r["source_hashes_at_solve"] == r9_evaluation_science_hashes() || error("保存期间依赖改变")
    ispath(dest) && error("保存期间目标已被其他会话创建")
    mv(staging, dest)
    dest
end

"""
    read_r9_reserve_day(directory)

核验文件集合/哈希和依赖版本，从原变量重算单日模型、费用与事件；不运行优化。
当前源码不匹配时须使用批次冻结模块调用本函数，不自动迁移或改写历史记录。
"""
function read_r9_reserve_day(directory::AbstractString)
    dest = abspath(directory)
    m = TOML.parsefile(joinpath(dest, "files.toml"))
    m["schema"] == "r9-reserve-day-artifact-v1" || error("日记录版本错误")
    Set(keys(m["files"])) == Set(["policy.toml", "trajectory.toml", "result.toml"]) &&
    Set(readdir(dest)) == union(Set(keys(m["files"])), Set(["files.toml"])) ||
        error("日文件集合改变")
    for (name, hash) in m["files"]
        bytes2hex(sha256(read(joinpath(dest, name)))) == hash || error("日文件字节改变")
    end
    p = R9ReservePolicy(TOML.parsefile(joinpath(dest, "policy.toml")))
    rows = TOML.parsefile(joinpath(dest, "trajectory.toml"))["values"]
    length(rows) == 2 && all(row->length(row)==p.data["template"]["T"], rows) ||
        error("保存轨迹形状错误")
    x = reduce(vcat, [permutedims(Float64.(row)) for row in rows])
    r = TOML.parsefile(joinpath(dest, "result.toml"))
    r["source_hashes_at_solve"] == r9_evaluation_science_hashes() ||
        error("日依赖不同，请使用冻结模块重读")
    v = validate_r9_reserve_day(p, x, r)
    r5_risk_validation_text(r9_compact_day_validation(v)) ==
    r5_risk_validation_text(r["validation"]) || error("保存的日摘要不同")
    (; policy = p, trajectory = x, result = r, validation = v)
end
