include("r6_pilot_replay.jl")

const R6_WORKSPACE_REPORTERS = ["scripts/report_r6_study.jl", "scripts/r6_study_tables.jl"]

function r6_workspace_path(root, rel)
    (
        !isempty(rel) &&
        !isabspath(rel) &&
        !occursin(':', rel) &&
        !occursin('\\', rel) &&
        all(x -> !(x in ("", ".", "..")), split(rel, '/'))
    ) || error("隔离路径须为规范相对路径")
    joinpath(root, split(rel, '/')...)
end

function r6_workspace_parent(batch)
    path = joinpath(batch, "freeze.toml")
    bytes2hex(sha256(read(path))) == strip(read(joinpath(batch, "freeze.sha256"), String)) ||
        error("父冻结清单改变")
    m = TOML.parsefile(path)
    m["schema"] == "r6-study-freeze-v1" || error("父批次类型错误")
    bytes2hex(sha256(read(joinpath(batch, "source.tar")))) == m["archive_sha256"] ||
        error("父源码归档改变")
    for h in Tar.list(joinpath(batch, "source.tar"))
        h.type in (:file, :directory) || error("源码归档不能含链接")
        r6_workspace_path(batch, rstrip(h.path, '/'))
    end
    m
end

"""
从R6冻结归档建立独立执行目录，原科学代码和数据逐字节复制。
报告脚本另从同一源码提交取出并单独登记；不改原批次、不优化、不更改规则或预算。
"""
function prepare_r6_workspace(batch, output; repository = normpath(joinpath(@__DIR__, "..")))
    VERSION == v"1.12.6" || error("隔离环境须使用Julia 1.12.6")
    ispath(output) && error("不覆盖已有冻结执行目录")
    m = r6_workspace_parent(batch)
    dataset = r6_workspace_path(repository, m["spec"]["dataset"])
    bytes2hex(sha256(read(joinpath(dataset, "manifest.toml")))) == m["data_manifest_sha256"] ||
        error("待复制的数据集不是冻结原值")
    inputs = r6_replay_inventory(dataset)
    # 先准备字节和验证路径，再创建新目录；中断留下的目录必须人工审计，不自动删除重建。
    extras = Dict(
        p => read(Cmd(["git", "-C", repository, "show", m["source_commit"]*":"*p])) for
        p in R6_WORKSPACE_REPORTERS
    )
    mkpath(output)
    Tar.extract(joinpath(batch, "source.tar"), output)
    r6_replay_inventory(output) == m["sources"] || error("隔离源码与归档不一致")
    dest = r6_workspace_path(output, m["spec"]["dataset"])
    mkpath(dirname(dest))
    cp(dataset, dest)
    r6_replay_inventory(dest) == inputs || error("隔离数据复制改变原值")
    for (p, bytes) in extras
        path = r6_workspace_path(output, p)
        ispath(path) && error("报告程序与科学源码重复")
        mkpath(dirname(path))
        write(path, bytes)
    end
    metadata = Dict(
        "schema" => "r6-frozen-execution-workspace-v1",
        "freeze_sha256" => bytes2hex(sha256(read(joinpath(batch, "freeze.toml")))),
        "source_commit" => m["source_commit"],
        "archive_sha256" => m["archive_sha256"],
        "sources" => m["sources"],
        "dataset" => m["spec"]["dataset"],
        "data_files" => inputs,
        "reporters" => Dict(p => bytes2hex(sha256(bytes)) for (p, bytes) in extras),
        "scientific_sources_unchanged" => true,
        "purpose" => "execute_existing_frozen_protocol_while_main_workspace_advances",
    )
    open(joinpath(output, "execution.toml"), "w") do io
        TOML.print(io, metadata; sorted = true)
    end
    check_r6_workspace(batch, output; repository)
end

"""只读核对隔离目录与父批次的源码、数据、报告程序及完整文件集合。"""
function check_r6_workspace(batch, workspace; repository = normpath(joinpath(@__DIR__, "..")))
    m = r6_workspace_parent(batch)
    meta = TOML.parsefile(joinpath(workspace, "execution.toml"))
    meta["schema"] == "r6-frozen-execution-workspace-v1" &&
    meta["scientific_sources_unchanged"] === true || error("隔离目录声明错误")
    meta["freeze_sha256"] == bytes2hex(sha256(read(joinpath(batch, "freeze.toml")))) &&
    meta["sources"] == m["sources"] &&
    meta["source_commit"] == m["source_commit"] &&
    meta["archive_sha256"] == m["archive_sha256"] &&
    meta["dataset"] == m["spec"]["dataset"] || error("隔离目录与父冻结不匹配")
    Set(keys(meta["reporters"])) == Set(R6_WORKSPACE_REPORTERS) || error("报告依赖不完整")
    # 报告程序不在原科学归档中，须重新绑定冻结提交，不能只信任可一同改写的自报哈希。
    for p in R6_WORKSPACE_REPORTERS
        original = read(Cmd(["git", "-C", repository, "show", m["source_commit"]*":"*p]))
        meta["reporters"][p] == bytes2hex(sha256(original)) || error("报告程序不是冻结提交原值")
    end
    expected = Dict{String,String}(meta["sources"])
    merge!(expected, meta["reporters"])
    for (p, h) in meta["data_files"]
        r6_workspace_path(workspace, p)
        expected[meta["dataset"]*"/"*p] = h
    end
    actual = r6_replay_inventory(workspace)
    pop!(actual, "execution.toml")
    actual == expected || error("隔离目录有缺失、额外文件或哈希变化")
    data = r6_workspace_path(workspace, meta["dataset"])
    bytes2hex(sha256(read(joinpath(data, "manifest.toml")))) == m["data_manifest_sha256"] ||
        error("隔离数据的冻结身份改变")
    dm = TOML.parsefile(joinpath(data, "manifest.toml"))
    for (p, h) in dm["files"]
        bytes2hex(sha256(read(r6_workspace_path(data, p)))) == h || error("数据清单与原值不同")
    end
    println("Frozen R6 execution sources and data match the original study; no optimization.")
    meta
end

"""
在已核验隔离目录执行原R6入口。仅改变执行路径；主工作区后续改动不会替代冻结科学实现。
保留原进程退出状态，不自动重试或改变求解器。费用、风险和失败仍按原协议记录。
"""
function run_r6_workspace(batch, workspace, action; report = nothing)
    VERSION == v"1.12.6" || error("执行版本错误")
    check_r6_workspace(batch, workspace)
    base = abspath(batch)
    work = abspath(workspace)
    if action in ("train", "validation", "select", "test", "stress", "check")
        report === nothing || error("训练/评估动作不接受报告路径")
        script = joinpath(work, "scripts/r6_study.jl")
        args = [action, base]
    elseif action in ("report-snapshot", "report-create", "report-check")
        report === nothing && error("报告动作需要显式路径")
        script = joinpath(work, "scripts/report_r6_study.jl")
        args = [replace(action, "report-" => ""), base, abspath(report)]
    else
        error("不支持的冻结动作")
    end
    root = normpath(joinpath(@__DIR__, ".."))
    depots = unique(vcat([joinpath(root, ".julia")], DEPOT_PATH))
    sep = Sys.iswindows() ? ';' : ':'
    env = copy(ENV)
    env["JULIA_DEPOT_PATH"] = join(depots, sep)
    env["JULIA_LOAD_PATH"] = join(["@", "@stdlib"], sep)
    # 避免隔离目录向上发现当前开发仓库，错误地把新HEAD当作旧科学源码的提交身份。
    env["GIT_CEILING_DIRECTORIES"] = dirname(work)
    command = `$(Base.julia_cmd()) --startup-file=no --project=$work $script $args`
    run(setenv(Cmd(command; dir = work), env))
    check_r6_workspace(batch, workspace)
    nothing
end

if abspath(PROGRAM_FILE) == @__FILE__
    length(ARGS) in (3, 4, 5) || error(
        "usage: r6_frozen_workspace.jl prepare|check <batch> <new-workspace> | run <batch> <workspace> <action> [report]",
    )
    mode, batch, workspace = ARGS[1:3]
    if mode == "prepare" && length(ARGS) == 3
        prepare_r6_workspace(batch, workspace)
    elseif mode == "check" && length(ARGS) == 3
        check_r6_workspace(batch, workspace)
    elseif mode == "run" && length(ARGS) in (4, 5)
        run_r6_workspace(batch, workspace, ARGS[4]; report = length(ARGS) == 5 ? ARGS[5] : nothing)
    else
        error("隔离入口参数错误")
    end
end
