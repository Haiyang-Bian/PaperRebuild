const R6_EVALUATION_REPORT_FILE=@__FILE__

function r6_evaluation_science_paths()
    paths=r5_strategic_science_paths()
    root=normpath(joinpath(dirname(R6_EVALUATION_CORE_FILE), "..", ".."))
    for file in (
        R6_EVALUATION_CORE_FILE,
        R6_EVALUATION_MODEL_FILE,
        R6_EVALUATION_VERIFY_FILE,
        R6_EVALUATION_SOLVE_FILE,
        R6_EVALUATION_REPORT_FILE,
        R6_SUPPORT_EVALUATION_FILE,
        R6_METHOD_CORE_FILE,
        R6_METHOD_ALGORITHM_FILE,
        R5_DISPATCH_DUALITY_FILE,
        R5_BENDERS_CORE_FILE,
        R5_BENDERS_VERIFY_FILE,
        R5_RISK_SOLVE_FILE,
    )
        paths[replace(relpath(file, root), '\\'=>'/')]=file
    end
    for rel in ("src/core/r6_protocol.jl", "src/algorithms/r6_data.jl")
        paths[rel]=joinpath(root, split(rel, '/')...)
    end
    paths
end
r6_evaluation_science_hashes() =
    Dict(k=>bytes2hex(sha256(read(v))) for (k, v) in r6_evaluation_science_paths())

"""
    save_r6_evaluation(day, temperature_domain, result, directory)

原子保存诊断单日输入、物理温度域、完整阶段原值/乘子、源码和哈希；失败同样保留。
拒绝覆写或求解后源码变化。R6-E3对应完整日身份，不将小时拆成风险样本。
"""
function save_r6_evaluation(c::R5DispatchCase, domain, r, directory::AbstractString)
    v=validate_r6_evaluation(c, domain, r)
    r5_risk_validation_text(v)==r5_risk_validation_text(r["validation"]) ||
        error("诊断摘要与原值不一致")
    r6_save_day_files(Dict("case.toml"=>c.data, "domain.toml"=>domain), r, directory, "diagnostic")
end

function r6_evaluation_replay_files()
    files=["src/networks/fixed_flow_heat.jl"]
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
    append!(
        files,
        [
            "src/algorithms/r5_market_selection.jl",
            "src/core/r5_benders.jl",
            "src/verification/r5_benders.jl",
            "src/core/r6_protocol.jl",
            "src/algorithms/r6_data.jl",
            "src/core/r6_methods.jl",
            "src/algorithms/r6_methods.jl",
            "src/core/r6_evaluation.jl",
            "src/formulations/r6_evaluation.jl",
            "src/verification/r6_evaluation.jl",
            "src/algorithms/r6_evaluation.jl",
            "src/algorithms/r6_support_evaluation.jl",
            "src/reporting/r6_evaluation.jl",
        ],
    )
    files
end

function r6_save_day_files(inputs, r, directory, kind)
    dest=abspath(directory)
    ispath(dest) && error("不覆盖样本外日记录")
    r["source_hashes_at_solve"]==r6_evaluation_science_hashes() || error("单日求解后源码变化")
    mkpath(dirname(dest))
    staging=dest*".writing-"*string(uuid4())
    mkdir(staging)
    for (file, data) in inputs
        write(joinpath(staging, file), r5_market_text(data))
    end
    write(joinpath(staging, "result.toml"), r5_market_text(r))
    for (rel, file) in r6_evaluation_science_paths()
        target=joinpath(staging, "code", rel)
        mkpath(dirname(target))
        cp(file, target)
    end
    reader=kind=="diagnostic" ? "read_r6_evaluation" : "read_r6_policy_day"
    replay="module FrozenR6Evaluation\nusing JuMP,TOML,SHA,Dates,UUIDs,Random\n" *
           join("include(\"$rel\")\n" for rel in r6_evaluation_replay_files()) *
           "end\nx=FrozenR6Evaluation.$reader(joinpath(@__DIR__,\"..\"))\n" *
           "x.current_source_matches || error(\"Frozen dependency closure mismatch\")\n" *
           "println(x.validation[\"comfort_outcome\"],\" cost_complete=\",x.validation[\"cost_complete\"])\n"
    write(joinpath(staging, "code", "replay.jl"), replay)
    root=normpath(joinpath(dirname(R6_EVALUATION_CORE_FILE), "..", ".."))
    metadata=Dict{String,Any}("schema"=>"r6-day-artifact-v1", "kind"=>kind, "run_id"=>r["run_id"])
    try
        metadata["git_commit"]=readchomp(`git -C $root rev-parse HEAD`)
        metadata["git_status"]=read(`git -C $root status --short`, String)
    catch
        metadata["git_unavailable"]=true
    end
    write(joinpath(staging, "metadata.toml"), r5_market_text(metadata))
    r["source_hashes_at_solve"]==r6_evaluation_science_hashes() || error("单日存档期间源码变化")
    hashes=Dict(
        p=>bytes2hex(sha256(read(joinpath(staging, p)))) for p in r5_market_file_inventory(staging)
    )
    write(joinpath(staging, "hashes.toml"), r5_market_text(Dict("files"=>hashes)))
    ispath(dest) && error("保存期间目标被其他会话创建")
    mv(staging, dest)
    dest
end

"""
    read_r6_evaluation(directory)

核对完整文件清单、原值及源码快照哈希，并从保存数值重新验算；不求解或改写历史状态。
另报告当前验证依赖是否与求解时一致，不伪称更换验证器后仍在运行旧源码。
"""
function read_r6_evaluation(directory::AbstractString)
    r, metadata=r6_read_day_files(directory, "diagnostic")
    c=R5DispatchCase(TOML.parsefile(joinpath(directory, "case.toml")))
    domain=TOML.parsefile(joinpath(directory, "domain.toml"))
    v=validate_r6_evaluation(c, domain, r)
    matches=r["source_hashes_at_solve"]==r6_evaluation_science_hashes()
    matches &&
        r5_risk_validation_text(v)!=r5_risk_validation_text(r["validation"]) &&
        error("冻结诊断判定与原值不一致")
    (; case = c, domain, result = r, validation = v, metadata, current_source_matches = matches)
end

function r6_read_day_files(directory, kind)
    islink(directory) && error("日记录不能使用目录链接")
    hashes=TOML.parsefile(joinpath(directory, "hashes.toml"))["files"]
    Set(keys(hashes))==Set(r5_market_file_inventory(directory)) || error("单日记录清单改变")
    all(bytes2hex(sha256(read(joinpath(directory, k))))==v for (k, v) in hashes) ||
        error("单日记录被篡改")
    r=TOML.parsefile(joinpath(directory, "result.toml"))
    all(get(hashes, "code/"*k, "")==h for (k, h) in r["source_hashes_at_solve"]) ||
        error("冻结源码快照不完整")
    metadata=TOML.parsefile(joinpath(directory, "metadata.toml"))
    metadata["schema"]=="r6-day-artifact-v1" &&
    metadata["kind"]==kind &&
    metadata["run_id"]==r["run_id"] || error("诊断与正式策略日记录不可混用")
    r, metadata
end

"""
    save_r6_policy_day(policy, trajectory, result, directory)

向新目录原子保存固定日前策略、新日轨迹、分支/原值/原始对偶及源码环境。
费用失败或未知也保存；先独立重算摘要，拒绝覆盖、源码变化及状态篡改。R6-E3/E4。
"""
function save_r6_policy_day(p::R6Policy, v::AbstractMatrix, r, directory::AbstractString)
    validation=validate_r6_policy_day(p, v, r)
    r5_risk_validation_text(validation)==r5_risk_validation_text(r["validation"]) ||
        error("策略日摘要与原值不一致")
    r6_save_day_files(
        Dict("policy.toml"=>p.data, "trajectory.toml"=>Dict("values"=>r5_market_rows(v))),
        r,
        directory,
        "support_policy",
    )
end

"""
    read_r6_policy_day(directory)

只读核验来源、清单、数值、训练代表匹配与样本外事件；不重新优化，不回写历史。
current_source_matches区分当前验算与原源码；code/replay.jl可加载冻结依赖独立重验。
"""
function read_r6_policy_day(directory::AbstractString)
    r, metadata=r6_read_day_files(directory, "support_policy")
    p=R6Policy(TOML.parsefile(joinpath(directory, "policy.toml")), r["policy_sha256"])
    v=r5_market_array(TOML.parsefile(joinpath(directory, "trajectory.toml"))["values"])
    validation=validate_r6_policy_day(p, v, r)
    matches=r["source_hashes_at_solve"]==r6_evaluation_science_hashes()
    matches &&
        r5_risk_validation_text(validation)!=r5_risk_validation_text(r["validation"]) &&
        error("冻结策略日判定与原值不一致")
    (;
        policy = p,
        trajectory = v,
        result = r,
        validation,
        metadata,
        current_source_matches = matches,
    )
end
