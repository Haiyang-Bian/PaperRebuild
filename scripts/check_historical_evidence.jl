module HistoricalEvidenceReplay
using SHA, TOML, Tar

const ROOT = normpath(joinpath(@__DIR__, ".."))
const BATCHES = Dict(
    "r5-commitment" => (
        commit = "d82df21f4b38eb1dc216a57899729344e25e3f1c",
        checker = "check_r5_commitment_artifacts.jl",
    ),
    "r5-risk" => (
        commit = "73b4a3568ab9e6f5c18228a36f6fa0806a401904",
        checker = "check_r5_risk_artifacts.jl",
    ),
    "r5-strategic" => (
        commit = "db56b3f231397e549c1ea3792a580d1582555261",
        checker = "check_r5_strategic_artifacts.jl",
    ),
    "r5-strategic-benders" => (
        commit = "c7ed63925dd5fd430b4daee823261939b0e340fe",
        checker = "check_r5_strategic_benders_artifacts.jl",
    ),
)

"""
    verify_identity(original, current)

逐字节核对历史报告和封存清单的身份；当前源码演进不能重签旧报告或替换历史见证。
此检查仅确认来源，数值/KKT/费用仍由原版本完整验证器重新计算。
"""
function verify_identity(original, current)
    for file in ("report.toml", "artifact-hashes.toml")
        read(joinpath(original, file)) == read(joinpath(current, file)) ||
            error("历史报告身份变化：$file")
    end
    report = TOML.parsefile(joinpath(current, "report.toml"))
    report["origin"] == "synthetic" || error("历史输入来源错误")
    return report
end

"""
    prepare(batch; root=ROOT)

从固定Git提交提取旧验证器、科学源码、配置和环境到新临时目录，不修改工作区或原证据。
提交为公开证据首次封存版本，区别于报告内可能更早的求解提交。需要完整Git历史。
返回原报告路径及冻结执行目录；历史哈希不与后续人民币扩展的当前源码强行比较。
"""
function prepare(batch; root = ROOT)
    haskey(BATCHES, batch) || error("未知历史证据批次：$batch")
    spec = BATCHES[batch]
    occursin(r"^[0-9a-f]{40}$", spec.commit) || error("非完整提交标识")
    success(pipeline(`git -C $root cat-file -e $(spec.commit * "^{commit}")`; stderr = devnull)) ||
        error("缺少固定历史提交；请获取完整Git历史后重验")
    parent = joinpath(root, "tmp")
    mkpath(parent)
    snapshot = mktempdir(parent; prefix = "historical-evidence-")
    archive = joinpath(snapshot, "source.tar")
    report_rel = "results/summaries/" * batch
    paths =
        ["src", "scripts", "configs", "test", "tools", "Project.toml", "Manifest.toml", report_rel]
    batch == "r5-strategic-benders" && push!(paths, "results/summaries/r5-strategic")
    run(`git -C $root archive --format=tar --output=$archive $(spec.commit) -- $paths`)
    code = joinpath(snapshot, "code")
    Tar.extract(archive, code)
    original = joinpath(code, split(report_rel, '/')...)
    current = joinpath(root, split(report_rel, '/')...)
    meta = verify_identity(original, current)
    for (rel, hash) in meta["source_sha256"]
        bytes2hex(sha256(read(joinpath(code, split(rel, '/')...)))) == hash ||
            error("固定提交不包含报告所声明源码：$rel")
    end
    println("Historical evidence: ", batch, "; verification commit: ", spec.commit)
    return (; code, current, spec)
end

"""
    replay(batch; mode="artifacts")

在独立Julia进程中执行原版本完整检查；artifacts重算当前公开原值，study执行旧批次规则篡改测试。
不求解、不改阈值、不将当前实现的验证替代历史版本。子进程失败原样传播。
"""
function replay(batch; mode = "artifacts")
    mode in ("artifacts", "study") || error("未知历史核验模式")
    mode == "study" && batch != "r5-strategic-benders" && error("该批次没有study入口")
    x = prepare(batch)
    script = mode == "study" ? "test_r5_strategic_benders_study.jl" : x.spec.checker
    args = mode == "study" ? String[] : [x.current]
    command = `$(Base.julia_cmd()) --startup-file=no --threads=1 --project=$(x.code) $(joinpath(x.code, "scripts", script)) $args`
    load_path = Sys.iswindows() ? "@;@stdlib" : "@:@stdlib"
    run(addenv(Cmd(command; dir = x.code), "JULIA_LOAD_PATH" => load_path))
end

if abspath(PROGRAM_FILE) == @__FILE__
    length(ARGS) in (1, 2) || error("usage: check_historical_evidence.jl BATCH [artifacts|study]")
    replay(ARGS[1]; mode = length(ARGS) == 2 ? ARGS[2] : "artifacts")
end
end
