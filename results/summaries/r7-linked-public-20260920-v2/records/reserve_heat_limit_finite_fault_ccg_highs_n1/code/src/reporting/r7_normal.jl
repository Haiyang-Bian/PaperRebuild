function r7_normal_science_paths()
    root=normpath(joinpath(@__DIR__, "..", ".."))
    paths=unique(
        vcat(
            collect(keys(r7_recovery_science_paths())),
            [
                "src/core/r7_commitment.jl",
                "src/components/r7_commitment.jl",
                "src/verification/r7_commitment.jl",
                "src/networks/r7_pipe_state.jl",
                "src/networks/fixed_flow_heat.jl",
                "src/core/r7_normal.jl",
                "src/networks/r7_normal_transport.jl",
                "src/formulations/r7_normal.jl",
                "src/verification/r7_normal.jl",
                "src/algorithms/r7_normal.jl",
                "src/reporting/r7_normal.jl",
            ],
        ),
    )
    Dict(p=>joinpath(root, split(p, '/')...) for p in paths)
end
r7_normal_science_hashes() =
    Dict(p=>bytes2hex(sha256(read(path))) for (p, path) in r7_normal_science_paths())

function r7_normal_check_record(c, r)
    r["thermal_model"]==c.data["thermal_model"] && r["full_preplan_optimality_verified"]===false ||
        error("正常模型范围被改写")
    v=validate_r7_normal(c, r)
    isequal(v, r["validation"]) &&
    r["candidate_accepted"]==v["model_pass"] &&
    r["conditional_cost_complete"]==v["optimality_pass"] || error("正常数值与验收摘要不同")
    v
end

"""
    save_r7_normal(case, result, directory)

保存新的正常调度、逐约束残差、输入和全部科学源码；不覆盖旧目录。
求解后源码变化即拒绝保存，冻结code/replay.jl能够脱离当前工作树只读重验。
"""
function save_r7_normal(c::R7NormalCase, r, directory::AbstractString)
    r["source_hashes_at_solve"]==r7_normal_science_hashes() || error("正常求解后源码改变")
    r7_normal_check_record(c, r)
    dest=abspath(directory)
    ispath(dest)&&error("不覆盖旧正常运行")
    staging=dest*".writing-"*string(uuid4())
    mkpath(staging)
    write(joinpath(staging, "case.toml"), r7_text(c.data))
    write(joinpath(staging, "result.toml"), r7_text(r))
    metadata=Dict{String,Any}(
        "schema"=>"r7-normal-metadata-v1",
        "case_sha256"=>c.sha256,
        "run_id"=>r["run_id"],
        "origin"=>c.data["origin"],
        "scope"=>"conditional_prescribed_flow_not_full_preplan",
        "saved_utc"=>string(now(UTC)),
    )
    root=normpath(joinpath(@__DIR__, "..", ".."))
    if ispath(joinpath(root, ".git"))
        metadata["git_commit"]=readchomp(Cmd(["git", "-C", root, "rev-parse", "HEAD"]))
        metadata["git_status"]=read(Cmd(["git", "-C", root, "status", "--short"]), String)
    end
    write(joinpath(staging, "metadata.toml"), r7_text(metadata))
    hashes=Dict(
        p=>bytes2hex(sha256(read(joinpath(staging, p)))) for
        p in ("case.toml", "result.toml", "metadata.toml")
    )
    for (p, path) in r7_normal_science_paths()
        target=joinpath(staging, "code", split(p, '/')...)
        mkpath(dirname(target))
        cp(path, target)
        hashes["code/"*p]=bytes2hex(sha256(read(target)))
    end
    includes=[
        "core/r7_recovery.jl",
        "formulations/r7_recovery.jl",
        "verification/r7_recovery.jl",
        "algorithms/r7_recovery.jl",
        "reporting/r7_recovery.jl",
        "core/r7_commitment.jl",
        "components/r7_commitment.jl",
        "verification/r7_commitment.jl",
        "networks/r7_pipe_state.jl",
        "networks/fixed_flow_heat.jl",
        "core/r7_normal.jl",
        "networks/r7_normal_transport.jl",
        "formulations/r7_normal.jl",
        "verification/r7_normal.jl",
        "algorithms/r7_normal.jl",
        "reporting/r7_normal.jl",
    ]
    replay="module FrozenR7Normal\nusing JuMP,TOML,SHA,Dates,UUIDs\nconst MOI=JuMP.MOI\n" *
           join("include(\"src/$p\")\n" for p in includes) *
           "end\nx=FrozenR7Normal.read_r7_normal(joinpath(@__DIR__,\"..\"))\nprintln(x.result[\"status\"],\" model=\",x.validation[\"model_pass\"])\n"
    write(joinpath(staging, "code", "replay.jl"), replay)
    hashes["code/replay.jl"]=bytes2hex(sha256(codeunits(replay)))
    write(joinpath(staging, "files.toml"), r7_text(Dict("files"=>hashes)))
    mv(staging, dest)
    read_r7_normal(dest)
    dest
end

"""只读核验正常运行清单、原值、来源和科学源码，并独立回代；不重新优化。"""
function read_r7_normal(directory::AbstractString)
    hashes=TOML.parsefile(joinpath(directory, "files.toml"))["files"]
    required=Set(
        vcat(
            ["case.toml", "result.toml", "metadata.toml", "code/replay.jl"],
            ["code/"*p for p in keys(r7_normal_science_paths())],
        ),
    )
    Set(keys(hashes))==required || error("正常存档清单不完整")
    actual=Set(
        replace(relpath(joinpath(path, f), directory), '\\'=>'/') for
        (path, _, files) in walkdir(directory) for f in files
    )
    actual==union(required, Set(["files.toml"])) || error("正常存档有额外或缺失文件")
    for (p, hash) in hashes
        !isabspath(p)&&!occursin(':', p)&&!occursin('\\', p)&&all(
            s->!(s in ("", ".", "..")),
            split(p, '/'),
        ) || error("存档路径非法")
        bytes2hex(sha256(read(joinpath(directory, split(p, '/')...))))==hash ||
            error("正常存档被改变")
    end
    c=load_r7_normal_case(joinpath(directory, "case.toml"))
    r=TOML.parsefile(joinpath(directory, "result.toml"))
    meta=TOML.parsefile(joinpath(directory, "metadata.toml"))
    meta["schema"]=="r7-normal-metadata-v1" &&
    meta["case_sha256"]==c.sha256 &&
    meta["run_id"]==r["run_id"] &&
    meta["origin"]==c.data["origin"] &&
    meta["scope"]=="conditional_prescribed_flow_not_full_preplan" || error("正常存档身份或范围错误")
    r["source_hashes_at_solve"]==r7_normal_science_hashes() ||
        error("请用原存档code/replay.jl重验正常运行")
    all(get(hashes, "code/"*p, "")==hash for (p, hash) in r["source_hashes_at_solve"]) ||
        error("正常源码副本不符")
    v=r7_normal_check_record(c, r)
    (; case = c, result = r, validation = v)
end
