const R5_EXECUTION_REPORT_FILE = @__FILE__

function r5_execution_science_paths()
    paths = r5_strategic_science_paths()
    for (layer, file) in (
        ("core", R5_EXECUTION_CORE_FILE),
        ("formulations", R5_EXECUTION_MODEL_FILE),
        ("verification", R5_EXECUTION_VERIFY_FILE),
        ("algorithms", R5_EXECUTION_SOLVE_FILE),
        ("reporting", R5_EXECUTION_REPORT_FILE),
    )
        paths["src/$layer/r5_execution.jl"] = file
    end
    paths
end
r5_execution_science_hashes() =
    Dict(k=>bytes2hex(sha256(read(v))) for (k, v) in r5_execution_science_paths())

function r5_execution_payload_validation(p, r)
    p["kind"]==r["kind"] || error("执行记录类型不匹配")
    p["kind"]=="market_execution" && return validate_r5_market_execution(R5MarketCase(p["case"]), r)
    p["kind"]=="fixed_award_delivery" || error("未知执行记录类型")
    validate_r5_execution_delivery(
        R5StrategicCase(p["case"]),
        R5MarketCase(p["market_case"]),
        p["market"],
        r,
    )
end

"""
    save_r5_execution_run(payload, result, directory)

向新目录保存市场选择或固定成交交付的完整输入、原值、验证、源码快照及哈希。
payload显式包含kind、case；交付另含market_case/market。不覆盖既有运行。
不同目标、乘子来源和条件界始终分存；保存前重新验算。
"""
function save_r5_execution_run(p::AbstractDict, r, directory::AbstractString)
    r["source_hashes_at_solve"]==r5_execution_science_hashes() || error("保存前执行源码变化")
    v = r5_execution_payload_validation(p, r)
    r5_risk_validation_text(v)==r5_risk_validation_text(r["validation"]) || error("执行验收变化")
    dest = abspath(directory)
    ispath(dest) && error("不覆盖执行记录")
    mkpath(dirname(dest))
    stage = dest*".writing-"*string(uuid4())
    mkdir(stage)
    write(joinpath(stage, "input.toml"), r5_market_text(p))
    write(joinpath(stage, "result.toml"), r5_market_text(r))
    for (rel, file) in r5_execution_science_paths()
        target = joinpath(stage, "code", split(rel, '/')...)
        mkpath(dirname(target))
        cp(file, target)
    end
    files = ["src/networks/fixed_flow_heat.jl"]
    for topic in ("market", "dispatch", "commitment", "risk", "strategic"),
        layer in ("core", "formulations", "verification", "algorithms", "reporting")

        push!(files, "src/$layer/r5_$topic.jl")
    end
    append!(
        files,
        [
            "src/verification/r5_market_payment.jl",
            "src/verification/r5_dispatch_duality.jl",
            "src/formulations/r5_dispatch_dual.jl",
            "src/algorithms/r5_market_selection.jl",
        ],
    )
    append!(
        files,
        [
            "src/$layer/r5_execution.jl" for
            layer in ("core", "formulations", "verification", "algorithms", "reporting")
        ],
    )
    replay =
        "module FrozenR5Execution\nusing JuMP,TOML,SHA,Dates,UUIDs\n" *
        join("include(\"$file\")\n" for file in files) *
        "end\nx=FrozenR5Execution.read_r5_execution_run(joinpath(@__DIR__,\"..\"))\nprintln(x.validation)\n"
    write(joinpath(stage, "code", "replay.jl"), replay)
    root = normpath(joinpath(dirname(R5_EXECUTION_CORE_FILE), "..", ".."))
    meta = Dict{String,Any}(
        "schema"=>"r5-execution-run-v1",
        "run_id"=>r["run_id"],
        "origin"=>"synthetic",
        "saved_utc"=>string(now(UTC)),
    )
    try
        meta["git_commit"] = readchomp(Cmd(["git", "-C", root, "rev-parse", "HEAD"]))
        meta["git_status"] = read(Cmd(["git", "-C", root, "status", "--short"]), String)
    catch
        meta["git_unavailable"] = true
    end
    write(joinpath(stage, "metadata.toml"), r5_market_text(meta))
    files_hash = Dict(
        rel=>bytes2hex(sha256(read(joinpath(stage, split(rel, '/')...)))) for
        rel in r5_market_file_inventory(stage)
    )
    write(joinpath(stage, "hashes.toml"), r5_market_text(Dict("files"=>files_hash)))
    r["source_hashes_at_solve"]==r5_execution_science_hashes() || error("保存期间源码变化")
    ispath(dest) && error("保存期间目标被占用")
    mv(stage, dest)
    dest
end

"""
    read_r5_execution_run(directory)

只读核验输入、原值、源快照与清单哈希，独立重算执行/交付结果；拒绝篡改或科学源码漂移。
需要历史版本时使用随运行保存的code/replay.jl，不重求解或改写旧判定。
"""
function read_r5_execution_run(directory::AbstractString)
    root = abspath(directory)
    hashes = TOML.parsefile(joinpath(root, "hashes.toml"))["files"]
    Set(keys(hashes))==Set(filter(x->x!="hashes.toml", r5_market_file_inventory(root))) ||
        error("执行文件清单改变")
    for (file, h) in hashes
        bytes2hex(sha256(read(joinpath(root, split(file, '/')...))))==h || error("执行文件被修改")
    end
    p = TOML.parsefile(joinpath(root, "input.toml"))
    r = TOML.parsefile(joinpath(root, "result.toml"))
    r["source_hashes_at_solve"]==r5_execution_science_hashes() || error("使用冻结执行源码重读")
    v = r5_execution_payload_validation(p, r)
    r5_risk_validation_text(v)==r5_risk_validation_text(r["validation"]) || error("执行验收不同")
    (; payload = p, result = r, validation = v)
end
