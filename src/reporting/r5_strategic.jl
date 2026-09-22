const R5_STRATEGIC_REPORT_FILE = @__FILE__

function r5_strategic_science_paths()
    paths = r5_risk_science_paths()
    paths["src/verification/r5_market_payment.jl"] = R5_MARKET_PAYMENT_FILE
    paths["src/algorithms/r5_market_selection.jl"] = R5_MARKET_SELECTION_FILE
    for (layer, file) in (
        ("core", R5_STRATEGIC_CORE_FILE),
        ("formulations", R5_STRATEGIC_MODEL_FILE),
        ("verification", R5_STRATEGIC_VERIFY_FILE),
        ("algorithms", R5_STRATEGIC_SOLVE_FILE),
        ("reporting", R5_STRATEGIC_REPORT_FILE),
    )
        paths["src/$layer/r5_strategic.jl"] = file
    end
    paths
end
r5_strategic_science_hashes() =
    Dict(k=>bytes2hex(sha256(read(v))) for (k, v) in r5_strategic_science_paths())

"""
    save_r5_strategic_run(case, result, directory)

向新目录原子保存连续报价、所选下层KKT、独立下层与风险原值，以及输入/源码/环境哈希。
拒绝覆盖或求解后源码变化；原始乘子、优化乘子和不同目标的界始终分存。
"""
function save_r5_strategic_run(c::R5StrategicCase, r, directory::AbstractString)
    r["source_hashes_at_solve"] == r5_strategic_science_hashes() || error("策略求解后源码变化")
    v = validate_r5_strategic(c, r)
    r5_risk_validation_text(v) == r5_risk_validation_text(r["validation"]) || error("策略验收变化")
    r["cost_optimization_complete"] == (r["status"]=="solver_optimal"&&v["optimality_pass"]) ||
        error("策略费用状态错误")
    dest = abspath(directory)
    ispath(dest) && error("不得覆盖策略运行")
    mkpath(dirname(dest))
    stage = dest*".writing-"*string(uuid4())
    mkdir(stage)
    write(joinpath(stage, "case.toml"), r5_market_text(c.data))
    write(joinpath(stage, "result.toml"), r5_market_text(r))
    for (rel, path) in r5_strategic_science_paths()
        target = joinpath(stage, "code", split(rel, '/')...)
        mkpath(dirname(target))
        cp(path, target)
    end
    files = ["src/networks/fixed_flow_heat.jl"]
    for name in ("market", "dispatch"),
        layer in ("core", "formulations", "verification", "algorithms", "reporting")

        push!(files, "src/$layer/r5_$name.jl")
    end
    append!(
        files,
        [
            "src/verification/r5_market_payment.jl",
            "src/verification/r5_dispatch_duality.jl",
            "src/formulations/r5_dispatch_dual.jl",
        ],
    )
    for name in ("commitment", "risk", "strategic"),
        layer in ("core", "formulations", "verification", "algorithms", "reporting")

        push!(files, "src/$layer/r5_$name.jl")
    end
    push!(files, "src/algorithms/r5_market_selection.jl")
    replay =
        "module FrozenR5Strategic\nusing JuMP,TOML,SHA,Dates,UUIDs\n" *
        join("include(\"$rel\")\n" for rel in files) *
        "end\nx=FrozenR5Strategic.read_r5_strategic_run(joinpath(@__DIR__,\"..\"))\nprintln(x.validation[\"model_pass\"])\n"
    write(joinpath(stage, "code", "replay.jl"), replay)
    root = normpath(joinpath(dirname(R5_STRATEGIC_CORE_FILE), "..", ".."))
    meta = Dict{String,Any}(
        "schema"=>"r5-strategic-run-v1",
        "case_sha256"=>c.sha256,
        "run_id"=>r["run_id"],
        "origin"=>c.data["origin"],
        "saved_utc"=>string(now(UTC)),
    )
    try
        meta["git_commit"] = readchomp(Cmd(["git", "-C", root, "rev-parse", "HEAD"]))
        meta["git_status"] = read(Cmd(["git", "-C", root, "status", "--short"]), String)
    catch
        meta["git_unavailable"] = true
    end
    write(joinpath(stage, "metadata.toml"), r5_market_text(meta))
    hashes = Dict(
        rel=>bytes2hex(sha256(read(joinpath(stage, split(rel, '/')...)))) for
        rel in r5_market_file_inventory(stage)
    )
    write(
        joinpath(stage, "hashes.toml"),
        r5_market_text(Dict("schema"=>"r5-strategic-hashes-v1", "files"=>hashes)),
    )
    r["source_hashes_at_solve"] == r5_strategic_science_hashes() || error("策略存档期间源码变化")
    ispath(dest) && error("策略保存期间目标被创建")
    mv(stage, dest)
    dest
end

"""
    read_r5_strategic_run(directory)

只读核验文件清单、全部哈希、输入身份及独立数值验算，不重新求解。
冻结code/replay.jl可重验历史版本；成功标志仍区分市场、补救风险与上层费用认证。
"""
function read_r5_strategic_run(directory::AbstractString)
    dir = abspath(directory)
    islink(dir) && error("策略目录不得为符号链接")
    h = TOML.parsefile(joinpath(dir, "hashes.toml"))
    h["schema"] == "r5-strategic-hashes-v1" || error("策略哈希版本错误")
    inventory = r5_market_file_inventory(dir)
    sort!(collect(keys(h["files"]))) == inventory || error("策略文件清单变化")
    for rel in inventory
        bytes2hex(sha256(read(joinpath(dir, split(rel, '/')...)))) == h["files"][rel] ||
            error("策略存档篡改：$rel")
    end
    c = load_r5_strategic_case(joinpath(dir, "case.toml"))
    r = TOML.parsefile(joinpath(dir, "result.toml"))
    meta = TOML.parsefile(joinpath(dir, "metadata.toml"))
    r["schema"]=="r5-strategic-result-v1" &&
    r["version"]=="r5_strategic_checked_v1" &&
    meta["schema"]=="r5-strategic-run-v1" || error("策略记录版本错误")
    r["case_sha256"] == meta["case_sha256"] == c.sha256 && r["run_id"] == meta["run_id"] ||
        error("策略身份不符")
    for (rel, hash) in r["source_hashes_at_solve"]
        get(h["files"], "code/"*rel, nothing) == hash || error("策略科学快照不同")
    end
    v = validate_r5_strategic(c, r)
    r5_risk_validation_text(v) == r5_risk_validation_text(r["validation"]) ||
        error("策略历史验算不同")
    r["cost_optimization_complete"] == (r["status"]=="solver_optimal"&&v["optimality_pass"]) ||
        error("策略历史费用状态不同")
    (; case = c, result = r, validation = v, metadata = meta)
end
