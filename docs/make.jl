using Documenter
using PaperRebuild

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
        "项目文件索引" => "generated-inventory.md",
        "骨架 API" => "api.md",
    ],
)
