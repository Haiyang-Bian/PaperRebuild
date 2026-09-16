using Documenter
using PaperRebuild

include(joinpath(@__DIR__, "..", "scripts", "ch02_docs.jl"))
sync_ch02()

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
