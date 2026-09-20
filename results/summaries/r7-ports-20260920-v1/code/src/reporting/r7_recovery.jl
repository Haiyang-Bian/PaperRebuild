const R7_RECOVERY_REPORT_FILE = @__FILE__

function r7_recovery_science_paths()
    root=normpath(joinpath(@__DIR__, "..", ".."))
    files=[
        "src/core/r7_recovery.jl",
        "src/formulations/r7_recovery.jl",
        "src/verification/r7_recovery.jl",
        "src/algorithms/r7_recovery.jl",
        "src/reporting/r7_recovery.jl",
        "src/PaperRebuild.jl",
        "Project.toml",
        "Manifest.toml",
    ]
    Dict(p=>joinpath(root, split(p, '/')...) for p in files)
end
r7_recovery_science_hashes() =
    Dict(p=>bytes2hex(sha256(read(path))) for (p, path) in r7_recovery_science_paths())

"""保存新的固定故障恢复运行、原值、残差、输入与源码快照；失败也保留，不覆盖旧目录。"""
function save_r7_recovery(c::R7RecoveryCase, r, directory::AbstractString)
    r["schema"]=="r7-recovery-result-v1" && r["version"]==r7_recovery_version(c) ||
        error("结果版本错误")
    r["source_hashes_at_solve"]==r7_recovery_science_hashes() || error("求解后恢复源码改变")
    checked=validate_r7_recovery(c, r)
    isequal(checked, r["validation"]) || error("残差摘要与原值不一致")
    r["candidate_accepted"]==checked["model_pass"] &&
    r["loss_optimization_complete"]==(checked["model_pass"]&&checked["optimality_pass"]) ||
        error("恢复结果状态不一致")
    dest=abspath(directory)
    ispath(dest) && error("不覆盖旧恢复运行")
    staging=dest*".writing-"*string(uuid4())
    mkpath(staging)
    write(joinpath(staging, "case.toml"), r7_text(c.data))
    write(joinpath(staging, "result.toml"), r7_text(r))
    root = normpath(joinpath(@__DIR__, "..", ".."))
    meta = Dict{String,Any}(
        "schema"=>"r7-recovery-metadata-v1",
        "run_id"=>r["run_id"],
        "case_sha256"=>c.sha256,
        "origin"=>c.data["origin"],
        "saved_utc"=>string(now(UTC)),
        "git_status_scope"=>"at_save_not_claimed_clean_or_formal",
    )
    if ispath(joinpath(root, ".git"))
        try
            meta["git_commit"] = readchomp(Cmd(["git", "-C", root, "rev-parse", "HEAD"]))
            meta["git_status"] = read(Cmd(["git", "-C", root, "status", "--short"]), String)
        catch
            meta["git_unavailable"] = true
        end
    else
        # 冻结源码不向上搜索外部仓库，避免错误归属当前开发提交。
        meta["git_unavailable"] = true
    end
    write(joinpath(staging, "metadata.toml"), r7_text(meta))
    hashes=Dict(
        "case.toml"=>bytes2hex(sha256(read(joinpath(staging, "case.toml")))),
        "result.toml"=>bytes2hex(sha256(read(joinpath(staging, "result.toml")))),
        "metadata.toml"=>bytes2hex(sha256(read(joinpath(staging, "metadata.toml")))),
    )
    for (p, path) in r7_recovery_science_paths()
        target=joinpath(staging, "code", split(p, '/')...)
        mkpath(dirname(target))
        cp(path, target)
        hashes["code/"*p]=bytes2hex(sha256(read(target)))
    end
    replay="module FrozenR7\nusing JuMP,TOML,SHA,Dates,UUIDs\nconst MOI=JuMP.MOI\n" *
           join(
               "include(\"src/$layer/r7_recovery.jl\")\n" for
               layer in ("core", "formulations", "verification", "algorithms", "reporting")
           ) *
           "end\nx=FrozenR7.read_r7_recovery(joinpath(@__DIR__,\"..\"))\nprintln(x.result[\"status\"], \" model=\", x.validation[\"model_pass\"])\n"
    write(joinpath(staging, "code", "replay.jl"), replay)
    hashes["code/replay.jl"]=bytes2hex(sha256(codeunits(replay)))
    write(joinpath(staging, "files.toml"), r7_text(Dict("files"=>hashes)))
    mv(staging, dest)
    read_r7_recovery(dest)
    dest
end

"""只读核验已保存恢复值、源码身份与全部残差；源码升级后使用存档code/replay.jl，不重新优化。"""
function read_r7_recovery(directory::AbstractString)
    hashes=TOML.parsefile(joinpath(directory, "files.toml"))["files"]
    required = Set(
        vcat(
            ["case.toml", "result.toml", "metadata.toml", "code/replay.jl"],
            ["code/"*p for p in keys(r7_recovery_science_paths())],
        ),
    )
    Set(keys(hashes)) == required || error("恢复存档文件清单不完整或有额外条目")
    actual = Set(
        replace(relpath(joinpath(path, f), directory), '\\'=>'/') for
        (path, _, files) in walkdir(directory) for f in files
    )
    actual == union(required, Set(["files.toml"])) || error("恢复存档存在未登记文件或缺失文件")
    for (p, hash) in hashes
        !isabspath(p) &&
        !occursin(':', p) &&
        !occursin('\\', p) &&
        all(s->!(s in ("", ".", "..")), split(p, '/')) || error("存档路径错误")
        bytes2hex(sha256(read(joinpath(directory, split(p, '/')...))))==hash ||
            error("恢复存档被改变")
    end
    c=load_r7_recovery_case(joinpath(directory, "case.toml"))
    r=TOML.parsefile(joinpath(directory, "result.toml"))
    meta=TOML.parsefile(joinpath(directory, "metadata.toml"))
    meta["schema"] == "r7-recovery-metadata-v1" &&
    meta["run_id"] == r["run_id"] &&
    meta["case_sha256"] == c.sha256 &&
    meta["origin"] == c.data["origin"] || error("恢复运行来源与原值身份不同")
    r["source_hashes_at_solve"]==r7_recovery_science_hashes() || error("请使用冻结源码重读恢复运行")
    for (p, hash) in r["source_hashes_at_solve"]
        get(hashes, "code/"*p, "")==hash || error("恢复源码副本缺失或不同")
    end
    val=validate_r7_recovery(c, r)
    isequal(val, r["validation"]) || error("恢复数值与摘要不一致")
    r["candidate_accepted"]==val["model_pass"] &&
    r["loss_optimization_complete"]==(val["model_pass"]&&val["optimality_pass"]) ||
        error("恢复通过状态被改写")
    (; case = c, result = r, validation = val)
end
