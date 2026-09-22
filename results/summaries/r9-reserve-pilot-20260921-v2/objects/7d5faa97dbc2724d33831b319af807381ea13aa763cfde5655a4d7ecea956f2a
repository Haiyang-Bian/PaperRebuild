const R5_COMMITMENT_REPORT_FILE=@__FILE__

function r5_commitment_science_paths()
    paths=r5_dispatch_science_paths()
    paths["src/verification/r5_dispatch_duality.jl"]=R5_DISPATCH_DUALITY_FILE
    paths["src/formulations/r5_dispatch_dual.jl"]=R5_DISPATCH_DUAL_MODEL_FILE
    for (layer, file) in (
        ("core", R5_COMMITMENT_CORE_FILE),
        ("formulations", R5_COMMITMENT_MODEL_FILE),
        ("verification", R5_COMMITMENT_VERIFY_FILE),
        ("algorithms", R5_COMMITMENT_SOLVE_FILE),
        ("reporting", R5_COMMITMENT_REPORT_FILE),
    )
        paths["src/$layer/r5_commitment.jl"]=file
    end
    paths
end
r5_commitment_science_hashes() =
    Dict(k=>bytes2hex(sha256(read(v))) for (k, v) in r5_commitment_science_paths())

function r5_commitment_validation_text(v)
    d=deepcopy(v)
    sort!(d["rows"]; by = x->(x["group"], x["id"]))
    for item in values(d["scenarios"])
        sort!(item["validation"]["rows"]; by = x->(x["group"], x["id"], x["entity"], x["t"]))
    end
    r5_market_text(d)
end

"""
    save_r5_commitment_run(case, result, directory)

保存共同承诺输入、全部情景原值/原始乘子、独立验算和科学源码快照，失败记录同样保留。
新目录原子发布，已有目录、篡改的验收摘要或变化的源码一律拒绝；不提交或推送Git。
"""
function save_r5_commitment_run(c::R5CommitmentCase, r, directory::AbstractString)
    r["schema"]=="r5-commitment-result-v1"&&r["version"]=="r5_shared_commitment_checked_v1"||error(
        "共同承诺结果版本错误",
    )
    r["source_hashes_at_solve"]==r5_commitment_science_hashes()||error("求解后共同承诺源码变化")
    v=validate_r5_commitment(c, r)
    r5_commitment_validation_text(v)==r5_commitment_validation_text(r["validation"])||error(
        "共同承诺验算不一致",
    )
    r["cost_optimization_complete"]==(r["status"]=="solver_optimal"&&v["optimality_pass"])||error(
        "费用完成标志错误",
    )
    dest=abspath(directory)
    ispath(dest)&&error("不覆盖共同承诺运行")
    mkpath(dirname(dest))
    stage=dest*".writing-"*string(uuid4())
    mkdir(stage)
    write(joinpath(stage, "case.toml"), r5_market_text(c.data))
    write(joinpath(stage, "result.toml"), r5_market_text(r))
    for (rel, path) in r5_commitment_science_paths()
        target=joinpath(stage, "code", split(rel, '/')...)
        mkpath(dirname(target))
        cp(path, target)
    end
    files=["src/networks/fixed_flow_heat.jl"]
    for name in ("market", "dispatch"),
        layer in ("core", "formulations", "verification", "algorithms", "reporting")

        push!(files, "src/$layer/r5_$name.jl")
    end
    append!(
        files,
        ["src/verification/r5_dispatch_duality.jl", "src/formulations/r5_dispatch_dual.jl"],
    )
    for layer in ("core", "formulations", "verification", "algorithms", "reporting")
        push!(files, "src/$layer/r5_commitment.jl")
    end
    replay="module FrozenR5Commitment\nusing JuMP,TOML,SHA,Dates,UUIDs\n" *
           join("include(\"$rel\")\n" for rel in files) *
           "end\nx=FrozenR5Commitment.read_r5_commitment_run(joinpath(@__DIR__,\"..\"))\nprintln(x.result[\"run_id\"],\" model=\",x.validation[\"model_pass\"],\" kkt=\",x.validation[\"kkt_pass\"])\n"
    write(joinpath(stage, "code", "replay.jl"), replay)
    root=normpath(joinpath(dirname(R5_COMMITMENT_CORE_FILE), "..", ".."))
    meta=Dict{String,Any}(
        "schema"=>"r5-commitment-run-v1",
        "run_id"=>r["run_id"],
        "case_sha256"=>c.sha256,
        "origin"=>c.data["origin"],
        "saved_utc"=>string(now(UTC)),
    )
    try
        meta["git_commit"]=readchomp(`git -C $root rev-parse HEAD`)
        meta["git_status"]=read(`git -C $root status --short`, String)
    catch
        meta["git_unavailable"]=true
    end
    write(joinpath(stage, "metadata.toml"), r5_market_text(meta))
    hashes=Dict(
        rel=>bytes2hex(sha256(read(joinpath(stage, split(rel, '/')...)))) for
        rel in r5_market_file_inventory(stage)
    )
    write(
        joinpath(stage, "hashes.toml"),
        r5_market_text(Dict("schema"=>"r5-commitment-hashes-v1", "files"=>hashes)),
    )
    r["source_hashes_at_solve"]==r5_commitment_science_hashes()||error(
        "存档期间源码变化；保留未发布目录",
    )
    ispath(dest)&&error("保存期间目录被创建")
    mv(stage, dest)
    dest
end

"""
    read_r5_commitment_run(directory)

只读核验共同承诺运行的文件清单、来源/源码哈希和全部情景的物理、费用、条件及整体KKT。
额外文件、篡改或验收变化拒绝；返回case/result/validation/metadata，不重新求解。
"""
function read_r5_commitment_run(directory::AbstractString)
    dir=abspath(directory)
    islink(dir)&&error("不允许运行目录符号链接")
    h=TOML.parsefile(joinpath(dir, "hashes.toml"))
    h["schema"]=="r5-commitment-hashes-v1"||error("共同承诺哈希版本错误")
    inventory=r5_market_file_inventory(dir)
    sort!(collect(keys(h["files"])))==inventory||error("共同承诺文件清单改变")
    for rel in inventory
        bytes2hex(sha256(read(joinpath(dir, split(rel, '/')...))))==h["files"][rel]||error(
            "共同承诺文件篡改：$rel",
        )
    end
    c=load_r5_commitment_case(joinpath(dir, "case.toml"))
    r=TOML.parsefile(joinpath(dir, "result.toml"))
    meta=TOML.parsefile(joinpath(dir, "metadata.toml"))
    r["schema"]=="r5-commitment-result-v1"&&r["version"]=="r5_shared_commitment_checked_v1"&&meta["schema"]=="r5-commitment-run-v1"||error(
        "共同承诺版本错误",
    )
    c.sha256==r["case_sha256"]==meta["case_sha256"]&&r["run_id"]==meta["run_id"]||error(
        "共同承诺身份错误",
    )
    for (rel, hash) in r["source_hashes_at_solve"]
        get(h["files"], "code/"*rel, nothing)==hash||error("共同承诺源码快照不一致")
    end
    v=validate_r5_commitment(c, r)
    r5_commitment_validation_text(v)==r5_commitment_validation_text(r["validation"])||error(
        "共同承诺历史验收变化",
    )
    r["cost_optimization_complete"]==(r["status"]=="solver_optimal"&&v["optimality_pass"])||error(
        "共同承诺费用状态错误",
    )
    (; case = c, result = r, validation = v, metadata = meta)
end
