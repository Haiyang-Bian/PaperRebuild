using Documenter
using PaperRebuild

include(joinpath(@__DIR__, "..", "scripts", "ch02_docs.jl"))
sync_ch02()
include(joinpath(@__DIR__, "..", "scripts", "ch03_docs.jl"))
sync_ch03()

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
            "R3可行性运行教程" => "ch03-r3.md",
            "R3可行性结果与图表" => "ch03-r3-results.md",
            "R3同模型求解器对照" => "ch03-r3-reference.md",
            "符号权威表" => "ch03-symbols.md",
            "运行与验收" => "ch03-r2.md",
            "合成实验结果与图表" => "ch03-r2-results.md",
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
