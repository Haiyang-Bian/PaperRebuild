const R5_BENDERS_REPORT_FILE=@__FILE__

function r5_benders_science_paths()
    paths=r5_risk_science_paths()
    for (layer, file) in (
        ("core", R5_BENDERS_CORE_FILE),
        ("formulations", R5_BENDERS_MODEL_FILE),
        ("verification", R5_BENDERS_VERIFY_FILE),
        ("algorithms", R5_BENDERS_SOLVE_FILE),
        ("reporting", R5_BENDERS_REPORT_FILE),
    )
        paths["src/$layer/r5_benders.jl"]=file
    end
    paths
end

"""
    save_r5_benders_run(case, result, directory)

原子保存全部迭代、条件割、情景原始乘子、风险/费用对手与科学源码，不覆盖已有目录。
失败与受限域记录同样保存；核验来源一致、独立重读及费用标志，不写Git或推送。
"""
function save_r5_benders_run(c::R5RiskCase, r, directory::AbstractString)
    get(r, "source_unchanged", false)&&r["source_hashes_at_solve"]==r5_benders_science_hashes()||error(
        "分解求解后源码改变",
    )
    v=validate_r5_benders(c, r)
    r5_risk_validation_text(v)==r5_risk_validation_text(r["validation"])||error("分解验收改变")
    r["cost_optimization_complete"]==(r["status"]=="full_domain_gap"&&v["optimality_pass"])||error(
        "分解费用状态错误",
    )
    dest=abspath(directory)
    ispath(dest)&&error("不覆盖分解运行")
    mkpath(dirname(dest))
    stage=dest*".writing-"*string(uuid4())
    mkdir(stage)
    write(joinpath(stage, "case.toml"), r5_market_text(c.data))
    write(joinpath(stage, "result.toml"), r5_market_text(r))
    for (rel, path) in r5_benders_science_paths()
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
    for name in ("commitment", "risk", "benders"),
        layer in ("core", "formulations", "verification", "algorithms", "reporting")

        push!(files, "src/$layer/r5_$name.jl")
    end
    replay="module FrozenR5Benders\nusing JuMP,TOML,SHA,Dates,UUIDs\n" *
           join("include(\"$rel\")\n" for rel in files) *
           "end\nx=FrozenR5Benders.read_r5_benders_run(joinpath(@__DIR__,\"..\"))\nprintln(x.result[\"run_id\"],\" model=\",x.validation[\"model_pass\"],\" optimal=\",x.validation[\"optimality_pass\"])\n"
    write(joinpath(stage, "code", "replay.jl"), replay)
    root=normpath(joinpath(dirname(R5_BENDERS_CORE_FILE), "..", ".."))
    meta=Dict{String,Any}(
        "schema"=>"r5-benders-run-v1",
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
        r5_market_text(Dict("schema"=>"r5-benders-hashes-v1", "files"=>hashes)),
    )
    r["source_hashes_at_solve"]==r5_benders_science_hashes()||error("分解存档期间源码改变")
    ispath(dest)&&error("分解保存期间目标被创建")
    mv(stage, dest)
    dest
end

"""
    read_r5_benders_run(directory)

检查文件清单、哈希、科学源码来源和全部迭代/割/概率/费用见证，只读且不求解。
允许使用保存的code/replay.jl重验；受限域历史不得改标为完整域最优。
"""
function read_r5_benders_run(directory::AbstractString)
    dir=abspath(directory)
    islink(dir)&&error("分解目录不允许符号链接")
    h=TOML.parsefile(joinpath(dir, "hashes.toml"))
    h["schema"]=="r5-benders-hashes-v1"||error("分解哈希版本错误")
    inventory=r5_market_file_inventory(dir)
    sort!(collect(keys(h["files"])))==inventory||error("分解文件清单变化")
    for rel in inventory
        bytes2hex(sha256(read(joinpath(dir, split(rel, '/')...))))==h["files"][rel]||error(
            "分解存档篡改：$rel",
        )
    end
    c=load_r5_risk_case(joinpath(dir, "case.toml"))
    r=TOML.parsefile(joinpath(dir, "result.toml"))
    meta=TOML.parsefile(joinpath(dir, "metadata.toml"))
    meta["schema"]=="r5-benders-run-v1"&&meta["case_sha256"]==c.sha256==r["case_sha256"]&&meta["run_id"]==r["run_id"]||error(
        "分解身份改变",
    )
    r["source_unchanged"]&&r["source_hashes_at_solve"]==r["source_hashes_at_return"]||error(
        "分解来源改变",
    )
    for (rel, hash) in r["source_hashes_at_solve"]
        get(h["files"], "code/"*rel, nothing)==hash||error("分解科学源码快照变化")
    end
    for src in values(r["subproblems"])
        src["source_hashes_at_solve"]==r["source_hashes_at_solve"]&&src["source_unchanged"]||error(
            "情景子问题来源不同",
        )
    end
    v=validate_r5_benders(c, r)
    r5_risk_validation_text(v)==r5_risk_validation_text(r["validation"])||error("分解历史验收不同")
    r["cost_optimization_complete"]==(r["status"]=="full_domain_gap"&&v["optimality_pass"])||error(
        "分解费用状态改变",
    )
    (; case = c, result = r, validation = v, metadata = meta)
end

"""
    compare_r5_benders_runs(left_directory, right_directory)

只读比较同输入分解运行或独立直接风险运行。不同输入拒绝；受限域只比较候选费用，不称同域最优间隙。
不会把参考解传入分解算法，不能仅由小系统时间作论文规模加速结论。
"""
function compare_r5_benders_runs(left::AbstractString, right::AbstractString)
    function load(dir)
        schema=TOML.parsefile(joinpath(dir, "metadata.toml"))["schema"]
        schema=="r5-benders-run-v1" ? read_r5_benders_run(dir) :
        schema=="r5-risk-run-v1" ? read_r5_risk_run(dir) : error("比较类型错误")
    end
    a, b=load(left), load(right)
    a.case.sha256==b.case.sha256||error("不能跨输入比较分解费用")
    usable(x) = x.validation["model_pass"]&&x.validation["risk_pass"]&&x.validation["cost_pass"]
    cost(x) = get(x.validation, "upper_bound", get(x.validation, "worst_net_cost", Inf))
    va, vb=cost(a), cost(b)
    comparable=usable(a)&&usable(b)
    gap=comparable ? abs(va-vb)/max(1.0, abs(va), abs(vb)) : Inf
    Dict(
        "case_sha256"=>a.case.sha256,
        "left_run_id"=>a.result["run_id"],
        "right_run_id"=>b.result["run_id"],
        "candidate_comparable"=>comparable,
        "left_cost"=>va,
        "right_cost"=>vb,
        "relative_cost_difference"=>gap,
        "a2_pass"=>comparable&&a.result["cost_optimization_complete"]&&b.result["cost_optimization_complete"]&&gap<=1e-4,
    )
end
