const R5_DISPATCH_REPORT_FILE = @__FILE__

function r5_dispatch_science_paths()
    paths=r5_market_science_paths()
    root=normpath(joinpath(dirname(R5_DISPATCH_CORE_FILE), "..", ".."))
    for (rel, path) in (
        "src/core/r5_dispatch.jl"=>R5_DISPATCH_CORE_FILE,
        "src/formulations/r5_dispatch.jl"=>R5_DISPATCH_MODEL_FILE,
        "src/verification/r5_dispatch.jl"=>R5_DISPATCH_VERIFY_FILE,
        "src/algorithms/r5_dispatch.jl"=>R5_DISPATCH_SOLVE_FILE,
        "src/reporting/r5_dispatch.jl"=>R5_DISPATCH_REPORT_FILE,
        "src/networks/fixed_flow_heat.jl"=>joinpath(root, "src", "networks", "fixed_flow_heat.jl"),
    )
        paths[rel]=path
    end
    paths
end
r5_dispatch_science_hashes() =
    Dict(rel=>bytes2hex(sha256(read(path))) for (rel, path) in r5_dispatch_science_paths())

function r5_dispatch_validation_text(v)
    d=deepcopy(v)
    sort!(d["rows"]; by = x->(x["group"], x["id"], x["entity"], x["t"]))
    r5_market_text(d)
end

"""
    save_r5_dispatch_run(case, result, directory)

原子保存新的确定性IES运行：完整输入、数值/状态、独立残差、依赖源码和锁文件快照。
重复路径或源码变化拒绝保存；失败运行也保存，原记录不可覆盖。生成冻结源码只读重放入口。
"""
function save_r5_dispatch_run(c::R5DispatchCase, r, directory::AbstractString)
    r5_dispatch_assert_case(c)
    r["schema"]=="r5-dispatch-result-v1" && r["version"]=="r5_dispatch_checked_v1" ||
        error("IES结果版本错误")
    r["source_hashes_at_solve"]==r5_dispatch_science_hashes() || error("求解后IES源码变化")
    check=validate_r5_dispatch(c, r)
    r5_dispatch_validation_text(check)==r5_dispatch_validation_text(r["validation"]) ||
        error("验收摘要不一致")
    r["cost_optimization_complete"]==(r["status"]=="solver_optimal"&&check["optimality_pass"]) ||
        error("费用状态错误")
    dest=abspath(directory)
    ispath(dest) && error("不覆盖已有IES运行")
    mkpath(dirname(dest))
    staging=dest*".writing-"*string(uuid4())
    mkdir(staging)
    write(joinpath(staging, "case.toml"), r5_market_text(c.data))
    write(joinpath(staging, "result.toml"), r5_market_text(r))
    for (rel, path) in r5_dispatch_science_paths()
        target=joinpath(staging, "code", split(rel, '/')...)
        mkpath(dirname(target))
        cp(path, target)
    end
    files=["src/networks/fixed_flow_heat.jl"]
    for name in ("market", "dispatch"),
        layer in ("core", "formulations", "verification", "algorithms", "reporting")

        push!(files, "src/$layer/r5_$name.jl")
    end
    replay="module FrozenR5Dispatch\nusing JuMP,TOML,SHA,Dates,UUIDs\n" *
           join("include(\"$rel\")\n" for rel in files) *
           "end\n" *
           "x=FrozenR5Dispatch.read_r5_dispatch_run(joinpath(@__DIR__,\"..\"))\n" *
           "println(x.result[\"run_id\"],\" model=\",x.validation[\"model_pass\"])\n"
    write(joinpath(staging, "code", "replay.jl"), replay)
    root=normpath(joinpath(dirname(R5_DISPATCH_CORE_FILE), "..", ".."))
    meta=Dict{String,Any}(
        "schema"=>"r5-dispatch-run-v1",
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
    write(joinpath(staging, "metadata.toml"), r5_market_text(meta))
    inventory=r5_market_file_inventory(staging)
    hashes=Dict(
        rel=>bytes2hex(sha256(read(joinpath(staging, split(rel, '/')...)))) for rel in inventory
    )
    write(
        joinpath(staging, "hashes.toml"),
        r5_market_text(Dict("schema"=>"r5-dispatch-hashes-v1", "files"=>hashes)),
    )
    r["source_hashes_at_solve"]==r5_dispatch_science_hashes() ||
        error("存档期间源码变化；保留未发布目录")
    ispath(dest) && error("保存期间目标目录被创建")
    mv(staging, dest)
    dest
end

"""
    read_r5_dispatch_run(directory)

核验确定性IES运行的完整文件清单、输入/源码哈希和历史状态，再独立重算数值约束与费用。
返回case/result/validation/metadata，不重新求解。额外文件、篡改和不一致完成标志均拒绝。
"""
function read_r5_dispatch_run(directory::AbstractString)
    dir=abspath(directory)
    islink(dir) && error("不允许运行目录符号链接")
    hashes=TOML.parsefile(joinpath(dir, "hashes.toml"))
    hashes["schema"]=="r5-dispatch-hashes-v1" || error("IES哈希版本错误")
    inventory=r5_market_file_inventory(dir)
    sort!(collect(keys(hashes["files"])))==inventory || error("IES文件清单变化")
    for rel in inventory
        hashes["files"][rel]==bytes2hex(sha256(read(joinpath(dir, split(rel, '/')...)))) ||
            error("IES文件篡改：$rel")
    end
    c=load_r5_dispatch_case(joinpath(dir, "case.toml"))
    r=TOML.parsefile(joinpath(dir, "result.toml"))
    meta=TOML.parsefile(joinpath(dir, "metadata.toml"))
    r["schema"]=="r5-dispatch-result-v1" &&
    r["version"]=="r5_dispatch_checked_v1" &&
    meta["schema"]=="r5-dispatch-run-v1" || error("IES版本错误")
    c.sha256==r["case_sha256"]==meta["case_sha256"] && r["run_id"]==meta["run_id"] ||
        error("IES身份错误")
    for (rel, hash) in r["source_hashes_at_solve"]
        get(hashes["files"], "code/"*rel, nothing)==hash || error("源码快照不一致")
    end
    v=validate_r5_dispatch(c, r)
    r5_dispatch_validation_text(v)==r5_dispatch_validation_text(r["validation"]) ||
        error("历史验收变化")
    r["cost_optimization_complete"]==(r["status"]=="solver_optimal"&&v["optimality_pass"]) ||
        error("费用完成标志错误")
    (; case = c, result = r, validation = v, metadata = meta)
end
