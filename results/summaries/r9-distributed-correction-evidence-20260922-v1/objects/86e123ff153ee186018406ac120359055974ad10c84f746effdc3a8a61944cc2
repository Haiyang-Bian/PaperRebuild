const R6_STUDY_CORE_FILE=@__FILE__

"""
    R6StudySpec(data)

正式R6小系统训练/验证/测试规则。六方法、五半径、500验证日与1000测试日在首次求解前固定。
风险合格且费用完整的候选中选最低验证均费；无合格候选执行明确回退并保持未通过标志。
训练的合格限时策略可评价，但不升级其最优性；对应R6-F1/F2，不能称作者同输入结果。
"""
struct R6StudySpec
    data::Dict{String,Any}
    sha256::String
end

function R6StudySpec(input::AbstractDict)
    d=deepcopy(Dict{String,Any}(string(k)=>v for (k, v) in input))
    expected=Dict(
        "schema"=>"r6-study-v1",
        "name"=>"r6_full_support_v1",
        "origin"=>"synthetic",
        "methods"=>R6_METHODS,
        "radii"=>[0.0, 0.0005, 0.001, 0.005, 0.01],
        "epsilon"=>0.05,
        "confidence"=>0.95,
        "training_support"=>100,
        "validation_days"=>500,
        "test_days"=>1000,
        "operation"=>"r6_support_nearest_v1",
        "diagnostic"=>"not_substituted_for_primary_policy",
        "primary_claim"=>"DRJCC_joint_comfort",
        "training_candidate"=>"independent_model_risk_cost_and_market_pass",
        "incomplete_training_optimum"=>"retain_feasible_policy_and_flag",
        "selection"=>"validated_minimum_mean_cost",
        "eligible"=>"risk_upper_at_most_epsilon_and_all_costs_complete",
        "fallback"=>"minimum_risk_upper_then_missing_costs_then_mean_then_radius",
        "cost_tie_USD"=>1e-8,
        "unknown"=>"keep_denominator_upper_counts_all",
        "test_gate"=>"selection_locked_after_all_validation",
        "training_budget_sec"=>600.0,
        "day_budget_sec"=>60.0,
        "training_solver"=>"gurobi",
        "recourse_solver"=>"highs",
        "threads"=>1,
        "solver_seed"=>23,
        "source_policy"=>"committed_and_snapshotted_before_first_solve",
        "warm_start"=>"none",
        "rerun"=>"never_replace_existing_outcome",
        "stress_cases"=>[
            "zero_pv_sustained_up",
            "zero_pv_sustained_down",
            "clear_pv_sustained_up",
            "clear_pv_sustained_down",
        ],
        "stress_statistic"=>"separate_deterministic_cases_no_iid_probability_claim",
        "solver_parameters"=>Dict(
            "gurobi"=>Dict(
                "Threads"=>1,
                "Seed"=>23,
                "FeasibilityTol"=>1e-9,
                "OptimalityTol"=>1e-9,
                "IntFeasTol"=>1e-9,
                "MIPGap"=>1e-9,
                "PreSOS1BigM"=>0,
                "DualReductions"=>0,
            ),
            "highs"=>Dict(
                "threads"=>1,
                "primal_feasibility_tolerance"=>1e-9,
                "dual_feasibility_tolerance"=>1e-9,
            ),
        ),
    )
    all(get(d, k, nothing)==v for (k, v) in expected) ||
        error("R6正式规则改变，须另建版本并重新冻结")
    Set(keys(d))==union(Set(keys(expected)), Set(["physical", "dataset"])) ||
        error("R6正式字段清单不符")
    for key in ("physical", "dataset")
        p=d[key]
        p isa String &&
        !isempty(p) &&
        !isabspath(p) &&
        !occursin(r"[:\\]", p) &&
        all(x->!isempty(x)&&!(x in (".", "..")), split(p, '/')) ||
            error("R6输入路径须为安全相对路径")
    end
    R6StudySpec(d, bytes2hex(sha256(r5_market_text(d))))
end

"""
    load_r6_study(path)

读取正式实验规则并计算规范化哈希；不读取验证/测试结果，也不运行优化。R6-F1。
"""
load_r6_study(path::AbstractString) = R6StudySpec(TOML.parsefile(path))
r6_assert_study(s) = bytes2hex(sha256(r5_market_text(s.data)))==s.sha256 || error("正式规则被修改")

"""
    r6_study_candidates(spec)

按冻结六方法顺序生成14项训练配置：D/SP/RO/CCP各一项，DRO/DRJCC各五个半径。
没有依据求解或验证结果筛选代表、半径或初值；D保持全部训练PV均值与零调用。R6-F1。
"""
function r6_study_candidates(s::R6StudySpec)
    r6_assert_study(s)
    result=Dict{String,Any}[]
    for method in s.data["methods"]
        radii=method in ("DRO", "DRJCC") ? s.data["radii"] : [0.0]
        for (j, radius) in enumerate(radii)
            id=method in ("DRO", "DRJCC") ? method*"-r"*lpad(j, 2, '0') : method
            push!(
                result,
                Dict(
                    "id"=>id,
                    "method"=>method,
                    "radius"=>radius,
                    "epsilon"=>s.data["epsilon"],
                    "order"=>length(result)+1,
                ),
            )
        end
    end
    result
end
