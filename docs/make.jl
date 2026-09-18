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
        ],
        "API 索引与说明" => "api.md",
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
