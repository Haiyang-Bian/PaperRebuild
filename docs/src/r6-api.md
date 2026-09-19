# R6 数据、方法与统计 API

本页读取Julia docstring。数据、日模型和六方法接口已经实现；样本外比较仍待执行。
模型解释见[六方法教程](r6-methods.md)，统计说明见[数据与统计教程](r6-data.md)，
新日操作见[策略外推与舒适诊断](r6-evaluation.md)。

```@index
Pages = ["r6-api.md"]
```

```@docs
PaperRebuild.R6Protocol
PaperRebuild.load_r6_protocol
PaperRebuild.R6TrajectorySet
PaperRebuild.r6_generate_trajectories
PaperRebuild.r6_fit_representatives
PaperRebuild.r6_support_distance
PaperRebuild.save_r6_dataset
PaperRebuild.read_r6_dataset
PaperRebuild.r6_binomial_bounds
PaperRebuild.r6_risk_evidence
PaperRebuild.r6_paired_costs
PaperRebuild.R6PhysicalCase
PaperRebuild.load_r6_physical_case
PaperRebuild.R6MethodSpec
PaperRebuild.r6_dispatch_day
PaperRebuild.r6_training_case
PaperRebuild.build_r6_model
PaperRebuild.solve_r6_training
PaperRebuild.R6EvaluationSpec
PaperRebuild.R6Policy
PaperRebuild.r6_policy_from_training
PaperRebuild.r6_evaluation_day
PaperRebuild.r6_support_label
PaperRebuild.build_r6_recourse
PaperRebuild.evaluate_r6_policy_day
PaperRebuild.validate_r6_policy_day
PaperRebuild.save_r6_policy_day
PaperRebuild.read_r6_policy_day
PaperRebuild.evaluate_r6_day
PaperRebuild.validate_r6_evaluation
PaperRebuild.save_r6_evaluation
PaperRebuild.read_r6_evaluation
PaperRebuild.R6StudySpec
PaperRebuild.load_r6_study
PaperRebuild.r6_study_candidates
PaperRebuild.r6_summarize_days
PaperRebuild.select_r6_methods
```
