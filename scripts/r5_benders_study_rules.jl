using PaperRebuild, TOML, SHA

"""只读验证分解实验规则、科学源码及输入；参考解只登记身份，不进入求解参数。"""
function r5_benders_study_inputs(config; root = normpath(joinpath(@__DIR__, "..")))
    rules=TOML.parsefile(config)
    rules["schema"]=="r5-benders-study-rules-v1"&&rules["origin"]=="synthetic"&&rules["frozen_before_optimization"]||error(
        "分解规则身份错误",
    )
    rules["budget_sec"]==600.0&&rules["oracle_solver"]=="clarabel"||error("分解预算或对手改变")
    rules["science_sha256"]==PaperRebuild.r5_benders_science_hashes()||error(
        "分解科学源码改变，须另建批次",
    )
    rules["spec"]==Dict(
        "critical_count"=>1,
        "max_iterations"=>200,
        "absolute_gap"=>1e-7,
        "relative_gap"=>1e-6,
        "cut_arithmetic"=>"rational_box",
        "diagnostic_scale"=>1024.0,
    )||error("分解预声明规则改变")
    cases=Dict{String,R5RiskCase}()
    for (file, hash) in rules["files"]
        basename(file)==file&&endswith(file, ".toml")||error("输入路径非法")
        path=joinpath(root, "configs", "r5", "risk", file)
        bytes2hex(sha256(read(path)))==hash||error("分解输入变化：$file")
        cases[file]=load_r5_risk_case(path)
    end
    length(cases)==13||error("正式输入范围不是原13套")
    expected=Set(
        (file, route, "highs") for file in keys(cases) for
        route in ("cuts", "critical", "paper_critical")
    )
    union!(
        expected,
        Set(
            (file, "critical", "gurobi") for
            file in ("hard_zero.toml", "thermal_e030_r005.toml", "future_e030_r005.toml")
        ),
    )
    runs=rules["runs"]
    length(runs)==42&&length(unique(e["id"] for e in runs))==42||error("运行清单重复或遗漏")
    Set((e["case"], e["route"], e["solver"]) for e in runs)==expected||error("运行因素改变")
    for e in runs
        e["id"]==splitext(e["case"])[1]*"--"*e["route"]*"--"*e["solver"]||error("运行标识非法")
        ref=rules["references"][e["case"]]
        ref["case_sha256"]==cases[e["case"]].sha256||error("参考输入不同")
        witness=joinpath(root, split(ref["witness"], '/')...)
        bytes2hex(sha256(read(witness)))==ref["witness_sha256"]||error("独立参考见证改变")
    end
    (; rules, cases)
end

function r5_benders_study_spec(rules, entry)
    d=deepcopy(rules["spec"])
    d["feasibility"]=entry["route"]
    PaperRebuild.r5_benders_spec(d)
end
