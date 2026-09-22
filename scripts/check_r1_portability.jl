# 导出当前工作区可提交文件，不读取或复制原件/缓存/运行目录；不创建 Git 提交。
using UUIDs

root = normpath(joinpath(@__DIR__, ".."))
target = joinpath(root, "tmp", "r1-export-" * string(uuid4()))
mkpath(target)
paths = split(
    read(
        Cmd(
            Cmd(["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"]);
            dir = root,
        ),
        String,
    ),
    '\0';
    keepempty = false,
)
for relative in paths
    startswith(relative, ".git/") && error("不应导出 Git 内部状态")
    relative in ("docs/摘要.pdf", "docs/摘要.docx") && error("原件意外进入可提交清单")
    source = normpath(joinpath(root, relative))
    destination = normpath(joinpath(target, relative))
    first(splitpath(relpath(destination, target))) == ".." && error("导出路径越界")
    isfile(source) || continue
    mkpath(dirname(destination))
    cp(source, destination)
end
isfile(joinpath(target, "docs", "摘要.pdf")) && error("原件不得导出")
julia = Base.julia_cmd()
for args in (
    ["--project=.", "scripts/check_ch02.jl"],
    ["--project=.", "test/runtests.jl"],
    ["--project=docs", "docs/make.jl"],
)
    run(Cmd(`$julia --startup-file=no $args`; dir = target))
end
println("Portable source export validated (not a Git clone): ", basename(target))
