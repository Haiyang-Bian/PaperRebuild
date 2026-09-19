using PaperRebuild, TOML, SHA

const R5_SB_PRODUCERS = (
    "study_r5_strategic_benders.jl",
    "r5_strategic_benders_study_rules.jl",
    "freeze_r5_strategic_benders.jl",
    "r5_strategic_setup.jl",
    "r5_risk_setup.jl",
    "r5_market_setup.jl",
)

"""只读核查策略分解正式输入、科学版本、三路线和后置参考身份；不读取参考解作求解参数。"""
function r5_sb_study_inputs(config; root = normpath(joinpath(@__DIR__, "..")))
    d = TOML.parsefile(config)
    d["schema"] == "r5-strategic-benders-study-rules-v1" &&
    d["origin"] == "synthetic" &&
    d["frozen_before_optimization"] || error("策略分解身份不符")
    d["science_sha256"] == PaperRebuild.r5_strategic_benders_science_hashes() ||
        error("科学源码变化，须另立研究版本")
    d["budget_sec"] == 600.0 &&
    d["master_solver"] == "gurobi" &&
    d["subproblem_solver"] == d["oracle_solver"] == "highs" || error("预算或求解器变化")
    d["selection"] == "optimistic_primal_dual" &&
    !d["reference_injected"] &&
    !d["price_caps_imposed"] &&
    d["market_domain"] == "full_SOS1" || error("策略域变化")
    d["initialization"] == "empty_cuts_and_critical_set" || error("初始化变化")
    d["spec"] == Dict(
        "critical_count"=>1,
        "max_iterations"=>200,
        "absolute_gap"=>1e-7,
        "relative_gap"=>1e-6,
        "cut_arithmetic"=>"rational_box",
        "diagnostic_scale"=>1024.0,
    ) || error("算法规则变化")
    parent = joinpath(root, "configs", "r5", "strategic", "study.toml")
    bytes2hex(sha256(read(parent))) == d["parent_rules_sha256"] || error("父输入规则变化")
    old = TOML.parsefile(parent)
    d["files"] == old["files"] && length(d["files"]) == 8 || error("必须沿用八套输入")
    Set(keys(d["producer_sha256"])) == Set(R5_SB_PRODUCERS) || error("执行依赖清单变化")
    for (file, hash) in d["producer_sha256"]
        bytes2hex(sha256(read(joinpath(root, "scripts", file)))) == hash ||
            error("执行入口变化：$file")
    end
    cases = Dict{String,R5StrategicCase}()
    for (file, hash) in d["files"]
        basename(file) == file && endswith(file, ".toml") || error("输入路径非法")
        path = joinpath(dirname(parent), file)
        bytes2hex(sha256(read(path))) == hash || error("输入改变：$file")
        cases[file] = load_r5_strategic_case(path)
        ref = d["references"][file]
        rel = "results/summaries/r5-strategic/witnesses/"*splitext(file)[1]*"-sos1.toml"
        ref["witness"] == rel && ref["case_sha256"] == cases[file].sha256 || error("参考身份不同")
        bytes2hex(sha256(read(joinpath(root, split(rel, '/')...)))) == ref["witness_sha256"] ||
            error("参考见证改变")
    end
    expected = Set(
        (file, route) for file in keys(cases) for route in ("cuts", "critical", "paper_critical")
    )
    runs = d["runs"]
    length(runs) == length(unique(e["id"] for e in runs)) == 24 &&
    Set((e["case"], e["route"]) for e in runs) == expected || error("三路线清单重复或遗漏")
    for e in runs
        Set(keys(e)) == Set(["id", "case", "route"]) || error("不得注入额外方法参数")
        e["id"] == splitext(e["case"])[1]*"--"*e["route"] || error("运行编号改变")
    end
    (; rules = d, cases)
end

function r5_sb_study_spec(rules, entry)
    d = deepcopy(rules["spec"])
    d["feasibility"] = entry["route"]
    PaperRebuild.r5_benders_spec(d)
end
