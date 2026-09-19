using Documenter
using PaperRebuild

include(joinpath(@__DIR__, "..", "scripts", "ch02_docs.jl"))
sync_ch02()
include(joinpath(@__DIR__, "..", "scripts", "ch03_docs.jl"))
sync_ch03()
include(joinpath(@__DIR__, "..", "scripts", "ch04_docs.jl"))
sync_ch04()
include(joinpath(@__DIR__, "..", "scripts", "r4_bargaining_docs.jl"))
sync_r4_bargaining()
include(joinpath(@__DIR__, "..", "scripts", "r4_tspa_docs.jl"))
sync_r4_tspa()
include(joinpath(@__DIR__, "..", "scripts", "r4_distributed_docs.jl"))
sync_r4_distributed()
include(joinpath(@__DIR__, "..", "scripts", "r4_network_docs.jl"))
sync_r4_network()
include(joinpath(@__DIR__, "..", "scripts", "r4_heat_docs.jl"))
sync_r4_heat_docs()
include(joinpath(@__DIR__, "..", "scripts", "r4_thermal_docs.jl"))
sync_r4_thermal_docs()
include(joinpath(@__DIR__, "..", "scripts", "r5_market_docs.jl"))
sync_r5_market_docs()
include(joinpath(@__DIR__, "..", "scripts", "r5_dispatch_docs.jl"))
sync_r5_dispatch_docs()
include(joinpath(@__DIR__, "..", "scripts", "r5_duality_docs.jl"))
sync_r5_duality_docs()
include(joinpath(@__DIR__, "..", "scripts", "r5_commitment_docs.jl"))
sync_r5_commitment_docs()
include(joinpath(@__DIR__, "..", "scripts", "r5_risk_docs.jl"))
sync_r5_risk_docs()
include(joinpath(@__DIR__, "..", "scripts", "r5_benders_docs.jl"))
sync_r5_benders_docs()
include(joinpath(@__DIR__, "..", "scripts", "r5_market_payment_docs.jl"))
sync_r5_market_payment_docs()
include(joinpath(@__DIR__, "..", "scripts", "r5_strategic_benders_docs.jl"))
sync_r5_strategic_benders_docs()
include(joinpath(@__DIR__, "..", "scripts", "r6_docs.jl"))
sync_r6_docs()
include(joinpath(@__DIR__, "..", "scripts", "ch06_docs.jl"))
sync_ch06_docs()
include(joinpath(@__DIR__, "..", "scripts", "r7_recovery_docs.jl"))
sync_r7_recovery_docs()
include(joinpath(@__DIR__, "..", "scripts", "r7_commitment_docs.jl"))
sync_r7_commitment_docs()
include(joinpath(@__DIR__, "..", "scripts", "r7_pipe_state_docs.jl"))
sync_r7_pipe_state_docs()
include(joinpath(@__DIR__, "..", "scripts", "r7_normal_docs.jl"))
sync_r7_normal_docs()
include(joinpath(@__DIR__, "..", "scripts", "r7_planning_docs.jl"))
sync_r7_planning_docs()
include(joinpath(@__DIR__, "..", "scripts", "r7_thermal_docs.jl"))
write(joinpath(@__DIR__, "src", "ch06-thermal-equations.md"), r7_thermal_markdown())

makedocs(;
    modules = [PaperRebuild],
    sitename = "PaperRebuild 复现手册",
    authors = "PaperRebuild contributors",
    source = joinpath(@__DIR__, "src"),
    build = joinpath(@__DIR__, "build"),
    remotes = nothing,
    warnonly = false,
    doctest = true,
    checkdocs = :all,
    format = Documenter.HTML(;
        prettyurls = true,
        lang = "zh-CN",
        edit_link = nothing,
        assets = ["assets/custom.css"],
        canonical = "https://haiyang-bian.github.io/PaperRebuild/",
        repolink = "https://github.com/Haiyang-Bian/PaperRebuild",
    ),
    pages = [
        "开始" => "index.md",
        "工具链" => "toolchain.md",
        "目录规范" => "structure.md",
        "工作流程" => "workflow.md",
        "质量规范" => "quality.md",
        "记录模板" => "templates.md",
        "论文阅读导航" => "reading.md",
        "论文主线与研究边界" => "thesis-overview.md",
        "审读证据与问题台账" => "thesis-audit.md",
        "逐阶段复现计划" => "reproduction-plan.md",
        "全文完成清单" => "reproduction-coverage.md",
        "验收与科学图表" => "reproduction-acceptance.md",
        "Julia 工具与架构" => "julia-design.md",
        "第3章数据搜集" => "ch03-data.md",
        "第3章 调度模型与可行性" => [
            "模型解释与补全" => "ch03-models.md",
            "设备、电网与水力公式" => "ch03-equations.md",
            "热网与简化公式" => "ch03-heat-equations.md",
            "算法公式与实现边界" => "ch03-algorithm-equations.md",
            "R3采用解释与推导" => "ch03-r3-theory.md",
            "R3灵敏度与投影梯度" => "ch03-r3-gradient.md",
            "R3稳健性与四模式" => "ch03-r3-robustness.md",
            "R3稳健性与四模式结果" => "ch03-r3-v2-results.md",
            "R3物理可行性与停止判据" => "ch03-r3-v3.md",
            "R3物理恢复与停止判据结果" => "ch03-r3-v3-results.md",
            "R3可比基线与差异归因" => "ch03-r3-baseline.md",
            "R3可比基线正式结果" => "ch03-r3-baseline-results.md",
            "R3投影梯度结果与图表" => "ch03-r3-pg-results.md",
            "R3可行性运行教程" => "ch03-r3.md",
            "R3可行性结果与图表" => "ch03-r3-results.md",
            "R3同模型求解器对照" => "ch03-r3-reference.md",
            "符号权威表" => "ch03-symbols.md",
            "运行与验收" => "ch03-r2.md",
            "合成实验结果与图表" => "ch03-r2-results.md",
        ],
        "第4章 集中交易与核算" => [
            "模型与账本解释" => "ch04-models.md",
            "原式清单" => "ch04-equations.md",
            "符号与采用解释" => "ch04-symbols.md",
            "运行与账本教程" => "ch04-tutorial.md",
            "首批实验与收益边界" => "ch04-results.md",
            "可实施分歧点与固定效用" => "ch04-baseline.md",
            "同制度协调收益与参与条件" => "ch04-baseline-results.md",
            "Nash分配与参与条件" => "ch04-bargaining.md",
            "议价公式与符号" => "ch04-bargaining-equations.md",
            "收益分配与补证结果" => "ch04-bargaining-results.md",
            "TSPA两阶段与网络分歧点" => "ch04-tspa.md",
            "TSPA公式与符号" => "ch04-tspa-equations.md",
            "TSPA分歧点与罚项结果" => "ch04-tspa-results.md",
            "分布协调推导与消息" => "ch04-distributed.md",
            "分布协调公式与符号" => "ch04-distributed-equations.md",
            "分布协调正式对照" => "ch04-distributed-results.md",
            "全部电池模式与精度核查" => "ch04-discrete.md",
            "离散模式正式结果" => "ch04-discrete-results.md",
            "网络重构解释与运行" => "ch04-network.md",
            "网络重构采用式与符号" => "ch04-network-equations.md",
            "重构结果与热模型缺口" => "ch04-network-results.md",
            "热状态相容性与重构" => "ch04-heat-compatibility.md",
            "热相容性公式与符号" => "ch04-heat-equations.md",
            "热状态重构与失败原因" => "ch04-heat-results.md",
            "循环与温度相关散热" => "ch04-thermal.md",
            "稳态热网采用式与符号" => "ch04-thermal-equations.md",
            "稳态循环与费用证据" => "ch04-thermal-results.md",
        ],
        "API 索引与说明" => "api.md",
        "第5章 市场与风险核查" => [
            "市场、备用与物理边界" => "ch05-market-audit.md",
            "固定报价出清与价格" => "ch05-market.md",
            "出清原式与符号" => "ch05-market-equations.md",
            "出清价格与原对偶结果" => "ch05-market-results.md",
            "成交与物理交付" => "ch05-dispatch.md",
            "补救原式与符号" => "ch05-dispatch-equations.md",
            "确定性补救与交付结果" => "ch05-dispatch-results.md",
            "补救最优性与灵敏度" => "ch05-recourse-duality.md",
            "补救对偶推导与符号" => "ch05-recourse-equations.md",
            "共同日前承诺与多情景" => "ch05-commitment.md",
            "共同承诺推导与符号" => "ch05-commitment-equations.md",
            "共同承诺正式结果" => "ch05-commitment-results.md",
            "有限支持风险调度" => "ch05-risk.md",
            "风险推导与符号" => "ch05-risk-equations.md",
            "风险调度结果与机制" => "ch05-risk-results.md",
            "条件分解基础与边界" => "ch05-benders.md",
            "条件分解推导与符号" => "ch05-benders-equations.md",
            "条件分解正式对照" => "ch05-benders-results.md",
            "求解器状态消歧与归因" => "ch05-benders-status.md",
            "策略报价准备与支付核算" => "ch05-strategic.md",
            "支付推导与符号" => "ch05-strategic-equations.md",
            "连续报价与风险连接" => "ch05-strategic-model.md",
            "策略模型公式与符号" => "ch05-strategic-model-equations.md",
            "策略收益与市场选择结果" => "ch05-strategic-results.md",
            "市场执行与实际交付" => "ch05-execution.md",
            "执行规则公式与符号" => "ch05-execution-equations.md",
            "成交执行与交付对照结果" => "ch05-execution-results.md",
            "连续报价与Benders连接" => "ch05-strategic-benders.md",
            "策略分解三路线正式结果" => "ch05-strategic-benders-results.md",
            "策略分解公式与符号" => "ch05-strategic-benders-equations.md",
            "联合机会约束概率方向" => "ch05-probability-audit.md",
            "分解算法与已知输入" => "ch05-algorithm-audit.md",
        ],
        "R6 样本外评估" => [
            "数据与统计教程" => "r6-data.md",
            "统一日模型与六方法" => "r6-methods.md",
            "开发实验结果与边界" => "r6-pilot-results.md",
            "新日策略与独立诊断" => "r6-evaluation.md",
            "新日公式与采用边界" => "r6-evaluation-equations.md",
            "正式训练与参数选择" => "r6-study.md",
            "选择公式与压力边界" => "r6-study-equations.md",
            "六方法推导与符号" => "r6-method-equations.md",
            "统计公式与来源核查" => "r6-equations.md",
            "数据与统计API" => "r6-api.md",
        ],
        "R6独立测试与压力结果" => "r6-test-results.md",
        "第6章 灾害与恢复核查" => [
            "量词、物理与算法证书" => "ch06-audit.md",
            "选定公式、符号与疑点" => "ch06-audit-equations.md",
            "给定灾前状态的恢复基准" => "ch06-recovery.md",
            "恢复采用式与符号" => "ch06-recovery-equations.md",
            "灾前启停与状态继承" => "ch06-commitment.md",
            "灾前启停推导与符号" => "ch06-commitment-equations.md",
            "管内温度与灾前显热" => "ch06-pipe-state.md",
            "管内状态参考推导与符号" => "ch06-pipe-equations.md",
            "正常调度与恢复状态连接" => "ch06-normal.md",
            "正常条件调度方程与符号" => "ch06-normal-equations.md",
            "有限故障经济安全规划" => "ch06-planning.md",
            "安全规划方程与符号" => "ch06-planning-equations.md",
            "内层故障搜索与不可行恢复" => "ch06-adversary.md",
            "内层对偶方程与符号" => "ch06-adversary-equations.md",
            "储热量与灾后热交付" => "ch06-thermal.md",
            "逐管热重构方程与符号" => "ch06-thermal-equations.md",
        ],
        "第 2 章模型与首批实现" => [
            "模型详解" => "ch02-models.md",
            "符号与代码命名" => "ch02-naming.md",
            "公式索引" => "ch02-generated.md",
            "符号权威表" => "ch02-symbols.md",
            "实现与测试映射" => "ch02-source.md",
            "API 导览与手算例" => "ch02-api.md",
            "运行教程与验收状态" => "ch02-status.md",
        ],
        "项目文件索引" => "generated-inventory.md",
    ],
)
