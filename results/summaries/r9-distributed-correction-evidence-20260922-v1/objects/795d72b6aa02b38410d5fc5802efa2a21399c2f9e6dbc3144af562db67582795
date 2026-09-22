const R5_STRATEGIC_BENDERS_CORE_FILE = @__FILE__

# 两个独立限制轴：市场互补分支是否固定、风险舒适域是否因原5-102缩小。
function r5_strategic_benders_scope(risk_scope, pattern)
    risk_scope in ("full_risk_domain", "restricted_comfort_domain") || error("未知风险域")
    if risk_scope == "full_risk_domain"
        pattern === nothing ? "full_optimistic_MPEC" : "fixed_complementarity_domain"
    else
        pattern === nothing ? "restricted_comfort_domain" :
        "fixed_complementarity_and_comfort_domain"
    end
end

function r5_strategic_benders_pattern(c, pattern)
    pattern === nothing && return nothing
    expected = keys(r5_strategic_market!(Model(), c).pairs)
    Set(keys(pattern)) == Set(expected) && all(v in (0, 1) for v in values(pattern)) ||
        error("固定市场互补分支须完整且每项为0或1")
    Dict{String,Int}(k=>Int(v) for (k, v) in pattern)
end

function r5_strategic_benders_source_check(r)
    get(r, "source_unchanged", false) &&
    r["source_hashes_at_solve"] == r["source_hashes_at_return"] ||
        error("策略分解科学源码在运行期间变化")
    old = r["subproblem_source_hashes"]
    Set(keys(old)) == Set(keys(r5_benders_science_paths())) &&
    Set(keys(r["source_hashes_at_solve"])) == Set(keys(r5_strategic_benders_science_paths())) ||
        error("策略分解科学快照缺少依赖文件")
    all(get(r["source_hashes_at_solve"], k, nothing) == v for (k, v) in old) ||
        error("情景子问题源码不属于分解快照")
end

r5_strategic_benders_candidate_pass(v) =
    v["model_pass"] &&
    v["risk_pass"] &&
    v["cost_pass"] &&
    v["independent_market_kkt_pass"] &&
    haskey(v, "worst_total_cost_USD")

function r5_strategic_benders_completion(r, v)
    finished = r["status"] == "declared_domain_gap" && v["domain_optimality_pass"]
    full = get(r, "complementarity_pattern", nothing) === nothing
    (; full = finished && full, branch = finished && !full)
end
