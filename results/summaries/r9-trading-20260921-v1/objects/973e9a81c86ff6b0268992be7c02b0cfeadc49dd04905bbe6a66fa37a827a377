const R5_RISK_REPORT_FILE=@__FILE__

function r5_risk_science_paths()
    paths=r5_commitment_science_paths()
    for (layer, file) in (
        ("core", R5_RISK_CORE_FILE),
        ("formulations", R5_RISK_MODEL_FILE),
        ("verification", R5_RISK_VERIFY_FILE),
        ("algorithms", R5_RISK_SOLVE_FILE),
        ("reporting", R5_RISK_REPORT_FILE),
    )
        paths["src/$layer/r5_risk.jl"]=file
    end
    paths
end
r5_risk_science_hashes() = Dict(k=>bytes2hex(sha256(read(v))) for (k, v) in r5_risk_science_paths())

function r5_risk_order(v)
    if v isa AbstractDict
        d=Dict{String,Any}(string(k)=>r5_risk_order(x) for (k, x) in v)
        haskey(d, "rows")&&sort!(d["rows"]; by = r5_market_text)
        return d
    elseif v isa AbstractVector
        return [r5_risk_order(x) for x in v]
    end
    v
end
r5_risk_validation_text(v) = r5_market_text(r5_risk_order(v))

"""
    save_r5_risk_run(case, result, directory)

新目录原子保存风险输入、原始策略、最坏费用/开关/实际事件的独立运输见证、分支参照与源码快照。
失败记录同样保存；拒绝覆盖、源码变动及验算不一致，不修改旧运行、不推送。
"""
function save_r5_risk_run(c::R5RiskCase, r, directory::AbstractString)
    r["schema"]=="r5-risk-result-v1"&&r["version"]=="r5_finite_support_checked_v1"||error(
        "风险结果版本错误",
    )
    r["source_hashes_at_solve"]==r5_risk_science_hashes()||error("求解后风险源码变化")
    v=validate_r5_risk(c, r)
    r5_risk_validation_text(v)==r5_risk_validation_text(r["validation"])||error("风险验收不一致")
    r["cost_optimization_complete"]==(
        r["status"] in ("solver_optimal", "enumeration_complete")&&v["optimality_pass"]
    )||error("风险费用完成标志错误")
    dest=abspath(directory)
    ispath(dest)&&error("不覆盖风险运行")
    mkpath(dirname(dest))
    stage=dest*".writing-"*string(uuid4())
    mkdir(stage)
    write(joinpath(stage, "case.toml"), r5_market_text(c.data))
    write(joinpath(stage, "result.toml"), r5_market_text(r))
    for (rel, path) in r5_risk_science_paths()
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
    for name in ("commitment", "risk"),
        layer in ("core", "formulations", "verification", "algorithms", "reporting")

        push!(files, "src/$layer/r5_$name.jl")
    end
    replay="module FrozenR5Risk\nusing JuMP,TOML,SHA,Dates,UUIDs\n" *
           join("include(\"$rel\")\n" for rel in files) *
           "end\nx=FrozenR5Risk.read_r5_risk_run(joinpath(@__DIR__,\"..\"))\nprintln(x.result[\"run_id\"],\" model=\",x.validation[\"model_pass\"],\" risk=\",x.validation[\"risk_pass\"])\n"
    write(joinpath(stage, "code", "replay.jl"), replay)
    root=normpath(joinpath(dirname(R5_RISK_CORE_FILE), "..", ".."))
    meta=Dict{String,Any}(
        "schema"=>"r5-risk-run-v1",
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
        r5_market_text(Dict("schema"=>"r5-risk-hashes-v1", "files"=>hashes)),
    )
    r["source_hashes_at_solve"]==r5_risk_science_hashes()||error("风险存档期间源码变化")
    ispath(dest)&&error("风险保存期间目标被创建")
    mv(stage, dest)
    dest
end

"""
    read_r5_risk_run(directory)

核验风险运行文件清单/哈希、输入、全部数值证书和费用状态；只读，不重新求解。
可由冻结code/replay.jl独立执行；不将现有证据扩大为未知情景或未实现的物理模型。
"""
function read_r5_risk_run(directory::AbstractString)
    dir=abspath(directory)
    islink(dir)&&error("风险目录不允许符号链接")
    h=TOML.parsefile(joinpath(dir, "hashes.toml"))
    h["schema"]=="r5-risk-hashes-v1"||error("风险哈希版本错误")
    inventory=r5_market_file_inventory(dir)
    sort!(collect(keys(h["files"])))==inventory||error("风险文件清单变化")
    for rel in inventory
        bytes2hex(sha256(read(joinpath(dir, split(rel, '/')...))))==h["files"][rel]||error(
            "风险存档篡改：$rel",
        )
    end
    c=load_r5_risk_case(joinpath(dir, "case.toml"))
    r=TOML.parsefile(joinpath(dir, "result.toml"))
    meta=TOML.parsefile(joinpath(dir, "metadata.toml"))
    r["schema"]=="r5-risk-result-v1"&&r["version"]=="r5_finite_support_checked_v1"&&meta["schema"]=="r5-risk-run-v1"||error(
        "风险存档版本错误",
    )
    c.sha256==r["case_sha256"]==meta["case_sha256"]&&r["run_id"]==meta["run_id"]||error(
        "风险存档身份错误",
    )
    for (rel, hash) in r["source_hashes_at_solve"]
        get(h["files"], "code/"*rel, nothing)==hash||error("风险科学源码快照变化")
    end
    v=validate_r5_risk(c, r)
    r5_risk_validation_text(v)==r5_risk_validation_text(r["validation"])||error("风险历史验收不同")
    r["cost_optimization_complete"]==(
        r["status"] in ("solver_optimal", "enumeration_complete")&&v["optimality_pass"]
    )||error("风险费用状态不一致")
    (; case = c, result = r, validation = v, metadata = meta)
end
