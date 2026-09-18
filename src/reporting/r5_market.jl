const R5_MARKET_REPORT_FILE = @__FILE__

function r5_market_science_paths()
    root=normpath(joinpath(dirname(R5_MARKET_CORE_FILE), "..", ".."))
    Dict(
        "src/core/r5_market.jl"=>R5_MARKET_CORE_FILE,
        "src/formulations/r5_market.jl"=>R5_MARKET_MODEL_FILE,
        "src/verification/r5_market.jl"=>R5_MARKET_VERIFY_FILE,
        "src/algorithms/r5_market.jl"=>R5_MARKET_SOLVE_FILE,
        "src/reporting/r5_market.jl"=>R5_MARKET_REPORT_FILE,
        "Project.toml"=>joinpath(root, "Project.toml"),
        "Manifest.toml"=>joinpath(root, "Manifest.toml"),
        "tools/solvers/Project.toml"=>joinpath(root, "tools", "solvers", "Project.toml"),
        "tools/solvers/Manifest.toml"=>joinpath(root, "tools", "solvers", "Manifest.toml"),
    )
end

function r5_market_science_hashes()
    Dict(rel=>bytes2hex(sha256(read(path))) for (rel, path) in r5_market_science_paths())
end

function r5_market_validation_text(v)
    d=deepcopy(v)
    sort!(d["rows"]; by = x->(x["scope"], x["id"], x["entity"], x["t"]))
    r5_market_text(d)
end

function r5_market_check_independent_dual(c, r)
    haskey(r, "independent_dual") || return nothing
    certificate=r["independent_dual"]
    if !haskey(certificate, "multipliers")
        certificate["verified"]===false || error("缺少独立对偶仍被标为通过")
        return nothing
    end
    trial=deepcopy(r)
    trial["multipliers"]=certificate["multipliers"]
    delete!(trial, "raw_duals")
    delete!(trial, "lower_bound_duals")
    check=validate_r5_market(c, trial)
    verified=all(x["pass"] for x in check["rows"]) &&
             abs(check["dual_value"]-certificate["objective"])<=1e-6*max(
        1.0,
        abs(certificate["objective"]),
    )
    certificate["verified"]==verified &&
    abs(certificate["dual_value_recomputed"]-check["dual_value"])<=1e-10 &&
    abs(certificate["relative_gap"]-check["relative_gap"])<=1e-12 || error("独立对偶证据不一致")
    nothing
end

function r5_market_file_inventory(dir)
    paths=String[]
    for (folder, dirs, files) in walkdir(dir)
        any(islink(joinpath(folder, d)) for d in dirs) && error("运行目录不允许符号链接")
        for f in files
            absolute=joinpath(folder, f)
            islink(absolute) && error("运行文件不允许符号链接")
            rel=replace(relpath(absolute, dir), '\\'=>'/')
            rel=="hashes.toml" || push!(paths, rel)
        end
    end
    sort!(paths)
end

"""
    save_r5_market_run(case, result, directory)

将市场运行保存到新的目录：规范化输入、完整数值/原对偶、独立残差、科学源码和环境快照。
核验求解时源码与当前源码一致后原子发布目录；已存在的运行不可覆盖。
目标为固定报价出清费用，不写作系统资源成本；保存失败运行但不制造候选。
"""
function save_r5_market_run(c::R5MarketCase, r, directory::AbstractString)
    r5_market_assert_case(c)
    r["schema"]=="r5-market-result-v1" && r["version"]=="r5_market_clearing_checked_v1" ||
        error("市场结果版本不支持")
    r["case_sha256"]==c.sha256 || error("市场输入与结果不一致")
    r["source_hashes_at_solve"]==r5_market_science_hashes() || error("求解后市场源码变化")
    fresh=validate_r5_market(c, r)
    r5_market_check_independent_dual(c, r)
    r5_market_validation_text(fresh)==r5_market_validation_text(r["validation"]) ||
        error("保存的验收摘要与独立回算不一致")
    complete=r["status"]=="solver_optimal"&&fresh["optimality_pass"]
    r["cost_optimization_complete"]==complete || error("费用完成状态与证据不一致")
    dest=abspath(directory)
    ispath(dest) && error("不覆盖已有市场运行")
    mkpath(dirname(dest))
    staging=dest*".writing-"*string(uuid4())
    mkdir(staging)
    write(joinpath(staging, "case.toml"), r5_market_text(c.data))
    write(joinpath(staging, "result.toml"), r5_market_text(r))
    for (rel, path) in r5_market_science_paths()
        target=joinpath(staging, "code", split(rel, '/')...)
        mkpath(dirname(target))
        cp(path, target)
    end
    root=normpath(joinpath(dirname(R5_MARKET_CORE_FILE), "..", ".."))
    replay="module FrozenR5Market\nusing JuMP, TOML, SHA, Dates, UUIDs\n" *
           join((
               "include(\""*rel*"\")\n" for rel in (
                   "src/core/r5_market.jl",
                   "src/formulations/r5_market.jl",
                   "src/verification/r5_market.jl",
                   "src/algorithms/r5_market.jl",
                   "src/reporting/r5_market.jl",
               )
           )) *
           "end\nloaded=FrozenR5Market.read_r5_market_run(joinpath(@__DIR__, \"..\"))\n" *
           "println(loaded.result[\"run_id\"], \" frozen model=\", loaded.validation[\"model_pass\"], \" kkt=\", loaded.validation[\"kkt_pass\"])\n"
    write(joinpath(staging, "code", "replay.jl"), replay)
    metadata=Dict{String,Any}(
        "schema"=>"r5-market-run-v1",
        "run_id"=>r["run_id"],
        "case_sha256"=>c.sha256,
        "origin"=>c.data["origin"],
        "source_scope"=>"Five market implementation files, root and optional solver environments",
        "module"=>string(@__MODULE__),
        "saved_utc"=>string(now(UTC)),
    )
    try
        metadata["git_commit"]=readchomp(`git -C $root rev-parse HEAD`)
        metadata["git_status"]=read(`git -C $root status --short`, String)
    catch
        metadata["git_status_unavailable"]=true
    end
    write(joinpath(staging, "metadata.toml"), r5_market_text(metadata))
    paths=r5_market_file_inventory(staging)
    hashes=Dict(
        rel=>bytes2hex(sha256(read(joinpath(staging, split(rel, '/')...)))) for rel in paths
    )
    write(
        joinpath(staging, "hashes.toml"),
        r5_market_text(Dict("schema"=>"r5-market-hashes-v1", "files"=>hashes)),
    )
    r["source_hashes_at_solve"]==r5_market_science_hashes() ||
        error("快照过程中市场源码变化；保留未发布目录")
    ispath(dest) && error("保存过程中目标目录被创建；不覆盖")
    mv(staging, dest)
    dest
end

"""
    read_r5_market_run(directory)

只读市场运行，核验完整文件清单、输入和源码快照哈希，再由保存数值独立回算约束与KKT。
返回case/result/validation/metadata；不重新求解，也不改写历史判定。
"""
function read_r5_market_run(directory::AbstractString)
    dir=abspath(directory)
    islink(dir) && error("运行目录不允许符号链接")
    index=TOML.parsefile(joinpath(dir, "hashes.toml"))
    index["schema"]=="r5-market-hashes-v1" || error("哈希清单版本错误")
    actual=r5_market_file_inventory(dir)
    sort!(collect(keys(index["files"])))==actual || error("运行文件清单变化")
    for rel in actual
        bytes2hex(sha256(read(joinpath(dir, split(rel, '/')...))))==index["files"][rel] ||
            error("运行文件篡改：$rel")
    end
    c=load_r5_market_case(joinpath(dir, "case.toml"))
    r=TOML.parsefile(joinpath(dir, "result.toml"))
    metadata=TOML.parsefile(joinpath(dir, "metadata.toml"))
    r["schema"]=="r5-market-result-v1"&&metadata["schema"]=="r5-market-run-v1" ||
        error("运行版本错误")
    r["case_sha256"]==metadata["case_sha256"]==c.sha256 || error("市场输入身份变化")
    r["run_id"]==metadata["run_id"] || error("市场运行ID变化")
    for (rel, hash) in r["source_hashes_at_solve"]
        key="code/"*rel
        get(index["files"], key, nothing)==hash || error("科学源码快照缺失或变化")
    end
    validation=validate_r5_market(c, r)
    r5_market_check_independent_dual(c, r)
    r5_market_validation_text(validation)==r5_market_validation_text(r["validation"]) ||
        error("市场历史验收与当前独立回算不一致")
    r["cost_optimization_complete"]==(
        r["status"]=="solver_optimal"&&validation["optimality_pass"]
    ) || error("市场费用完成状态错误")
    (; case = c, result = r, validation, metadata)
end

"""
    compare_r5_market_runs(left, right)

读取同输入、同出清版本的两条运行，比较独立回算目标和原对偶认证。
同模型费用差采用A2的1e-4；退化LP的不同价格/调度不强制相同。
失败或未取得候选时返回不可比较，不把缺失费用补零。
"""
function compare_r5_market_runs(left::AbstractString, right::AbstractString)
    a, b=read_r5_market_run(left), read_r5_market_run(right)
    a.case.sha256==b.case.sha256 || error("不能将不同市场输入作为同模型费用对照")
    for key in ("version", "objective_type")
        a.result[key]==b.result[key] || error("市场比较口径不一致：$key")
    end
    result=Dict{String,Any}(
        "left_run"=>a.result["run_id"],
        "right_run"=>b.result["run_id"],
        "case_sha256"=>a.case.sha256,
        "comparable"=>false,
        "A2_pass"=>false,
    )
    all(haskey(x.result, "values") for x in (a, b)) || return result
    va, vb=a.validation["clearing_objective"], b.validation["clearing_objective"]
    gap=abs(va-vb)/max(1.0, abs(va), abs(vb))
    result["comparable"]=true
    result["relative_objective_difference"]=gap
    result["A2_pass"]=gap<=1e-4&&a.validation["optimality_pass"]&&b.validation["optimality_pass"]
    result
end
