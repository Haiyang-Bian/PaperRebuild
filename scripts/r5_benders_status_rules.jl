include("r5_benders_study_rules.jl")

const R5_STATUS_CASES = ("hard_zero.toml", "thermal_e030_r005.toml", "future_e030_r005.toml")

"""验证仅改变子问题DualReductions的冻结对照；旧运行原值只用于重现失败点。"""
function r5_benders_status_inputs(config; root = normpath(joinpath(@__DIR__, "..")))
    rules=TOML.parsefile(config)
    rules["schema"]=="r5-benders-status-rules-v1"&&rules["origin"]=="synthetic" &&
    rules["frozen_before_optimization"]||error("状态复核规则身份错误")
    original=joinpath(root, "configs", "r5", "benders", "study.toml")
    bytes2hex(sha256(read(original)))==rules["parent_rules_sha256"]||error("原规则变化")
    input=r5_benders_study_inputs(original; root)
    rules["science_sha256"]==input.rules["science_sha256"]||error("科学模型变化")
    rules["probe_budget_sec"]==60.0&&rules["method_budget_sec"]==600.0||error("预算变化")
    rules["probe_values"]==[1, 0]&&rules["subproblem_DualReductions"]==0 &&
    rules["master_DualReductions"]==1||error("非单因素对照")
    length(rules["runs"])==3&&Set(e["case"] for e in rules["runs"])==Set(R5_STATUS_CASES)||error(
        "完整方法范围变化",
    )
    sources=Dict{String,Any}()
    parents=Dict{String,Any}()
    expected=Set{Tuple{String,String}}()
    for e in rules["runs"]
        file=e["case"]
        id=splitext(file)[1]*"--critical--gurobi"
        e["parent_id"]==id&&e["id"]==id*"--dr0"||error("运行身份错误")
        base=joinpath(root, "results", "summaries", "r5-benders", "witnesses", id)
        path=joinpath(base, "witness.toml")
        bytes2hex(sha256(read(path)))==e["parent_sha256"]||error("原见证变化")
        w=TOML.parsefile(path)
        R5RiskCase(w["case"]).sha256==input.cases[file].sha256||error("旧输入不同")
        parents[file]=w
        for (rel, hash) in w["source_files_sha256"]
            occursin(r"^subproblems/[A-Za-z0-9_-]+\.toml$", rel)||error("旧来源路径非法")
            srcpath=joinpath(base, split(rel, '/')...)
            bytes2hex(sha256(read(srcpath)))==hash||error("原子问题变化")
            s=TOML.parsefile(srcpath)
            if s["status"]=="INFEASIBLE_OR_UNBOUNDED"
                sources[s["run_id"]]=s
                push!(expected, (file, s["run_id"]))
            end
        end
    end
    length(rules["probes"])==5&&length(expected)==5 &&
    Set((p["case"], p["source_id"]) for p in rules["probes"])==expected||error("失败点遗漏或替换")
    length(unique(p["id"] for p in rules["probes"]))==5||error("失败点标识重复")
    for p in rules["probes"]
        occursin(r"^[A-Za-z0-9_-]+$", p["id"])||error("失败点路径标识非法")
        s=sources[p["source_id"]]
        p["scenario"]==s["scenario"]&&p["branch"]==s["branch"]&&!s["elastic"]||error(
            "失败点定义改变",
        )
        p["source_sha256"]==parents[p["case"]]["source_files_sha256"]["subproblems/"*s["run_id"]*".toml"]||error(
            "失败点哈希变化",
        )
    end
    (; rules, cases = input.cases, original_rules = input.rules, sources, parents)
end
