const R5_STRATEGIC_BENDERS_REPORT_FILE = @__FILE__

function r5_strategic_benders_science_paths()
    paths = merge(r5_benders_science_paths(), r5_strategic_science_paths())
    for (layer, file) in (
        ("core", R5_STRATEGIC_BENDERS_CORE_FILE),
        ("formulations", R5_STRATEGIC_BENDERS_MODEL_FILE),
        ("verification", R5_STRATEGIC_BENDERS_VERIFY_FILE),
        ("algorithms", R5_STRATEGIC_BENDERS_SOLVE_FILE),
        ("reporting", R5_STRATEGIC_BENDERS_REPORT_FILE),
    )
        paths["src/$layer/r5_strategic_benders.jl"] = file
    end
    paths
end
r5_strategic_benders_science_hashes() =
    Dict(k=>bytes2hex(sha256(read(v))) for (k, v) in r5_strategic_benders_science_paths())

function r5_strategic_benders_saved_check(c, r)
    v = validate_r5_strategic_benders(c, r)
    r5_risk_validation_text(v) == r5_risk_validation_text(r["validation"]) ||
        error("策略分解历史验算改变")
    completed = r5_strategic_benders_completion(r, v)
    r["cost_optimization_complete"] == completed.full &&
    r["declared_branch_cost_complete"] == completed.branch || error("策略分解费用证书的域改变")
    v
end

"""
    save_r5_strategic_benders_run(case, result, directory)

向新目录原子保存全部策略分解迭代、报价、市场原值、情景原始乘子、条件割和独立运输见证。
冻结科学源码及Julia环境，保存完整域/固定互补/受限舒适的区别；拒绝覆盖或运行期间源码改变。
失败和未完成记录同样保存，不写Git、不推送，不把主问题上图视为可交付完整策略。
"""
function save_r5_strategic_benders_run(c::R5StrategicCase, r, directory::AbstractString)
    r["source_hashes_at_solve"] == r5_strategic_benders_science_hashes() ||
        error("求解后策略分解源码变化")
    r5_strategic_benders_saved_check(c, r)
    dest = abspath(directory)
    ispath(dest) && error("不得覆盖策略分解记录")
    mkpath(dirname(dest))
    stage = dest*".writing-"*string(uuid4())
    mkdir(stage)
    write(joinpath(stage, "case.toml"), r5_market_text(c.data))
    write(joinpath(stage, "result.toml"), r5_market_text(r))
    for (rel, path) in r5_strategic_benders_science_paths()
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
    for name in ("commitment", "risk", "benders", "strategic", "strategic_benders"),
        layer in ("core", "formulations", "verification", "algorithms", "reporting")

        push!(files, "src/$layer/r5_$name.jl")
    end
    push!(files, "src/algorithms/r5_market_selection.jl")
    replay =
        "module FrozenR5StrategicBenders\nusing JuMP,TOML,SHA,Dates,UUIDs\n" *
        join("include(\"$rel\")\n" for rel in files) *
        "end\nx=FrozenR5StrategicBenders.read_r5_strategic_benders_run(joinpath(@__DIR__,\"..\"))\nprintln(x.result[\"run_id\"],\" model=\",x.validation[\"model_pass\"],\" full_optimal=\",x.validation[\"optimality_pass\"])\n"
    write(joinpath(stage, "code", "replay.jl"), replay)
    root = normpath(joinpath(dirname(R5_STRATEGIC_BENDERS_CORE_FILE), "..", ".."))
    mkpath(joinpath(stage, "environment"))
    for file in ("Project.toml", "Manifest.toml")
        cp(joinpath(root, file), joinpath(stage, "environment", file))
    end
    meta = Dict{String,Any}(
        "schema"=>"r5-strategic-benders-run-v1",
        "run_id"=>r["run_id"],
        "case_sha256"=>c.sha256,
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
        r5_market_text(Dict("schema"=>"r5-strategic-benders-hashes-v1", "files"=>hashes)),
    )
    r["source_hashes_at_solve"] == r5_strategic_benders_science_hashes() ||
        error("保存期间科学源码改变")
    ispath(dest) && error("保存期间目标目录已创建")
    mv(stage, dest)
    dest
end

"""
    read_r5_strategic_benders_run(directory)

只读核验清单、输入/源码/文件哈希、全部迭代及费用作用域，不调用任何求解器。
历史版本可执行随运行保存的code/replay.jl；不重写旧结果，不用新参考值修改失败判定。
"""
function read_r5_strategic_benders_run(directory::AbstractString)
    dir = abspath(directory)
    islink(dir) && error("策略分解目录不得为符号链接")
    h = TOML.parsefile(joinpath(dir, "hashes.toml"))
    h["schema"] == "r5-strategic-benders-hashes-v1" || error("策略分解哈希版本不符")
    inventory = r5_market_file_inventory(dir)
    sort!(collect(keys(h["files"]))) == inventory || error("策略分解文件清单变化")
    for rel in inventory
        bytes2hex(sha256(read(joinpath(dir, split(rel, '/')...)))) == h["files"][rel] ||
            error("策略分解存档篡改：$rel")
    end
    c = load_r5_strategic_case(joinpath(dir, "case.toml"))
    r = TOML.parsefile(joinpath(dir, "result.toml"))
    meta = TOML.parsefile(joinpath(dir, "metadata.toml"))
    meta["schema"] == "r5-strategic-benders-run-v1" &&
    meta["case_sha256"] == c.sha256 == r["case_sha256"] &&
    meta["run_id"] == r["run_id"] || error("策略分解身份不符")
    for (rel, hash) in r["source_hashes_at_solve"]
        get(h["files"], "code/"*rel, nothing) == hash || error("科学源码快照不符")
    end
    v = r5_strategic_benders_saved_check(c, r)
    (; case = c, result = r, validation = v, metadata = meta)
end

"""
    compare_r5_strategic_benders_runs(left_directory, right_directory)

只读比较同输入策略分解或独立直接SOS1运行；先校验文件、候选可交付与费用，再检查声明的策略域。
固定互补分支只有在两侧完全相同且未额外固定舒适分支时才比较同域A2，另列完整MPEC的A2。
直接参考不传入分解过程；不同输入拒绝，受限域只比较候选费用，不冒称全局最优差。
"""
function compare_r5_strategic_benders_runs(left::AbstractString, right::AbstractString)
    function load(dir)
        schema = TOML.parsefile(joinpath(dir, "metadata.toml"))["schema"]
        schema == "r5-strategic-benders-run-v1" ? read_r5_strategic_benders_run(dir) :
        schema == "r5-strategic-run-v1" ? read_r5_strategic_run(dir) : error("策略比较类型不符")
    end
    a, b = load(left), load(right)
    a.case.sha256 == b.case.sha256 || error("不能跨输入比较策略分解")
    usable(x) = all(
        x.validation[k] for
        k in ("model_pass", "risk_pass", "cost_pass", "independent_market_kkt_pass")
    )
    cost(x) = get(x.validation, "upper_bound", get(x.validation, "worst_total_cost_USD", Inf))
    complete(x) =
        x.result["cost_optimization_complete"] ||
        get(x.result, "declared_branch_cost_complete", false)
    same =
        get(a.result, "complementarity_pattern", nothing) ==
        get(b.result, "complementarity_pattern", nothing) &&
        !haskey(a.result, "risk_pattern") &&
        !haskey(b.result, "risk_pattern")
    ca, cb = cost(a), cost(b)
    comparable = usable(a) && usable(b)
    gap = comparable ? abs(ca-cb)/max(1.0, abs(ca), abs(cb)) : Inf
    a2 = comparable && same && complete(a) && complete(b) && gap <= 1e-4
    Dict(
        "case_sha256"=>a.case.sha256,
        "left_run_id"=>a.result["run_id"],
        "right_run_id"=>b.result["run_id"],
        "candidate_comparable"=>comparable,
        "same_declared_domain"=>same,
        "left_cost"=>ca,
        "right_cost"=>cb,
        "relative_cost_difference"=>gap,
        "a2_pass"=>a2,
        "full_model_a2_pass"=>a2 && !haskey(a.result, "complementarity_pattern"),
    )
end
