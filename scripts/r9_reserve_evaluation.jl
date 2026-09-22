# 固定所有训练来源后才运行新日；逐日追加、按原顺序恢复，不覆盖失败记录。
module R9ReserveEvaluationStudy
using PaperRebuild, TOML, SHA, Dates, UUIDs, JuMP, HiGHS, CSV
include("r9_seeded_study.jl")
include("seal_r9_seeded.jl")
const ROOT = dirname(@__DIR__)
const S = R9SeededStudy.S
hashfile(p) = bytes2hex(sha256(read(p)))
text(x) = PaperRebuild.r5_market_text(x)
toml(p, x) = write(p, text(x))
clock() = time_ns()/1e9
call(lib, name, args...; kwargs...) = S.call(lib, name, args...; kwargs...)

function check_protocol(p)
    p["schema"] == "r9-reserve-evaluation-study-v1" &&
    p["origin"] == "synthetic" &&
    p["currency"] == "CNY" &&
    p["schemes"] == ["3A", "3B", "3C"] || error("评价协议身份")
    p["test_days"] == 1000 &&
    p["day_budget_sec"] == 60.0 &&
    p["chunk_days"] == 50 &&
    p["prefix_measurement_days"] == 3 &&
    p["prefix_is_part_of_final_test"] &&
    !p["retry_completed_days"] &&
    !p["radius_tuning"] || error("评价样本或执行规则")
    p["evaluation_version"] == "r9_nearest_recourse_v1" &&
    p["information"] == "complete_trajectory" &&
    p["epsilon"] == 0.05 &&
    p["confidence"] == 0.95 &&
    p["unknown_rule"] == "keep_denominator_upper_counts_all" || error("评价操作或统计口径")
    true
end

"""锁定三项训练状态、实际候选、1000原测试日及公共源码；不优化或重新抽样。"""
function freeze(common, training, evidence, out)
    VERSION == v"1.12.6" || error("Julia版本")
    ispath(out) && error("不覆盖冻结输入")
    protocol = TOML.parsefile(joinpath(ROOT, "configs/r9/reserve-evaluation.toml"))
    check_protocol(protocol)
    parents = protocol["parents"]
    hashfile(joinpath(common, "manifest.toml")) == parents["common_sha256"] &&
    hashfile(joinpath(training, "manifest.toml")) == parents["training_freeze_sha256"] &&
    hashfile(joinpath(evidence, "delivery.toml")) == parents["training_evidence_sha256"] ||
        error("训练来源改变")
    R9SeededEvidence.check(common, training, evidence; replay = false)
    bound = R9SeededStudy.loadfreeze(common, training)
    b = bound.state.bundle
    b.spec.data["test_policy"] ==
    "nearest_frozen_representative_comfort_branch_full_trajectory_recourse" ||
        error("原协议未授权该操作")
    ordered = [
        PaperRebuild.r6_evaluation_replay_files();
        "src/verification/r6_statistics.jl";
        "src/core/r9_evaluation.jl";
        "src/algorithms/r9_evaluation.jl";
        "src/reporting/r9_evaluation.jl"
    ]
    paths = PaperRebuild.r9_evaluation_science_paths()
    for rel in ordered
        paths[rel] = S.safe(ROOT, rel)
    end
    for rel in (
        "Project.toml",
        "Manifest.toml",
        "scripts/r9_reserve_evaluation.jl",
        "scripts/r9_seeded_study.jl",
        "scripts/r9_reserve_witness.jl",
        "scripts/r9_reserve_study.jl",
        "scripts/seal_r9_seeded.jl",
        "configs/r9/reserve-evaluation.toml",
    )
        paths[rel] = S.safe(ROOT, rel)
    end
    before = Dict(k=>hashfile(v) for (k, v) in paths)
    mkpath(dirname(out))
    stage = mktempdir(dirname(out); prefix = basename(out)*".writing-")
    slots = Dict{String,Any}()
    policies = Dict{String,Any}()
    owners = Dict{String,String}()
    for scheme in protocol["schemes"]
        r = R9SeededStudy.read_numeric(joinpath(evidence, scheme, "run")).result
        r["case_sha256"] == bound.manifest["cases"][scheme] || error("训练输入身份")
        entry = Dict{String,Any}(
            "scheme"=>scheme,
            "training_status"=>r["status"],
            "training_run_id"=>r["run_id"],
            "training_case_sha256"=>r["case_sha256"],
            "training_result_sha256"=>PaperRebuild.r9_evaluation_hash(r),
            "training_cost_optimization_complete"=>get(r, "cost_optimization_complete", false),
        )
        if !get(r, "has_candidate", false)
            entry["status"] = "training_candidate_unavailable"
            entry["test_operation_defined"] = false
        else
            original = call(
                b.lib,
                :r9_reserve_risk_case,
                b.template,
                b.dataset.sets["train"],
                b.dataset.representatives,
                b.spec,
                scheme;
                pilot = false,
            )
            oldcheck = call(b.lib, :validate_r5_risk, original, r)
            all(oldcheck[k] for k in ("model_pass", "risk_pass", "cost_pass")) ||
                error("原训练候选重读失败")
            c = R5RiskCase(original.data)
            c.sha256 == original.sha256 == r["case_sha256"] || error("新旧输入解释不同")
            policy = r9_reserve_policy_from_training(c, r)
            policy.data["training"]["scheme"] == scheme || error("提取的训练方案标签不同")
            owner = get(owners, policy.operation_sha256, scheme)
            if owner != scheme
                PaperRebuild.r9_operation_data(policy.data) ==
                PaperRebuild.r9_operation_data(policies[owner].data) || error("操作哈希碰撞")
            end
            policies[scheme] = policy
            owners[policy.operation_sha256] = owner
            file = "policy-"*scheme*".toml"
            toml(joinpath(stage, file), policy.data)
            merge!(
                entry,
                Dict(
                    "status"=>"locked_verified_training_candidate",
                    "test_operation_defined"=>true,
                    "policy_file"=>file,
                    "policy_sha256"=>policy.sha256,
                    "operation_sha256"=>policy.operation_sha256,
                    "compute_owner"=>owner,
                ),
            )
            println(scheme, " locked; operation owner=", owner)
        end
        slots[scheme] = entry
        GC.gc()
    end
    # 测试数据此前独立生成；原始顺序和每个数值保持，不重新抽样或用结果挑选。
    test = b.dataset.sets["test"]
    length(test.ids) == protocol["test_days"] || error("测试日不完整")
    days = [
        Dict("id"=>test.ids[i], "values"=>PaperRebuild.r5_market_rows(test.values[:, :, i])) for
        i in eachindex(test.ids)
    ]
    toml(joinpath(stage, "test-days.toml"), Dict("days"=>days, "source_set_sha256"=>test.sha256))
    for (rel, source) in paths
        dest = S.safe(stage, "code/"*rel)
        mkpath(dirname(dest))
        cp(source, dest)
    end
    write(
        joinpath(stage, "code/library.jl"),
        "module FrozenR9Heldout\nusing JuMP,TOML,SHA,Dates,UUIDs,Random,CSV\n" *
        join("include(\"$rel\")\n" for rel in ordered) *
        "end\n",
    )
    all(hashfile(paths[k])==h==hashfile(S.safe(stage, "code/"*k)) for (k, h) in before) ||
        error("冻结期间源码改变")
    m=Dict(
        "schema"=>"r9-heldout-freeze-v1",
        "origin"=>"synthetic",
        "created_utc"=>string(now(UTC)),
        "julia_version"=>string(VERSION),
        "git_commit"=>readchomp(`git -C $ROOT rev-parse HEAD`),
        "git_status"=>read(`git -C $ROOT status --porcelain=v1`, String),
        "optimization_performed"=>false,
        "protocol"=>protocol,
        "slots"=>slots,
        "source_hashes"=>before,
        "science_hashes"=>PaperRebuild.r9_evaluation_science_hashes(),
        "test_set_sha256"=>test.sha256,
        "test_protocol_sha256"=>test.protocol_sha256,
        "files"=>Dict(p=>hashfile(S.safe(stage, p)) for p in S.inventory(stage)),
    )
    toml(joinpath(stage, "manifest.toml"), m)
    write(joinpath(stage, "manifest.sha256"), hashfile(joinpath(stage, "manifest.toml"))*"\n")
    ispath(out) && error("目标已存在")
    mv(stage, out)
    println("Locked all three training slots and 1000 test days; no test optimization.")
    m
end

function openfreeze(frozen)
    hashfile(joinpath(frozen, "manifest.toml")) ==
    strip(read(joinpath(frozen, "manifest.sha256"), String)) || error("冻结清单改变")
    m=TOML.parsefile(joinpath(frozen, "manifest.toml"))
    m["schema"]=="r9-heldout-freeze-v1" && !m["optimization_performed"] || error("冻结范围")
    check_protocol(m["protocol"])
    Set(S.inventory(frozen)) ==
    union(Set(keys(m["files"])), Set(["manifest.toml", "manifest.sha256"])) || error("冻结文件集合")
    for (rel, h) in m["files"]
        hashfile(S.safe(frozen, rel))==h || error("冻结文件改变: $rel")
    end
    w=Module(gensym(:R9HeldoutWrapper))
    Base.include(w, joinpath(frozen, "code/library.jl"))
    lib=Base.invokelatest(getfield, w, :FrozenR9Heldout)
    call(lib, :r9_evaluation_science_hashes)==m["science_hashes"] || error("冻结依赖不完整")
    raw=TOML.parsefile(joinpath(frozen, "test-days.toml"))
    days=raw["days"]
    length(days)==m["protocol"]["test_days"] &&
    length(unique(d["id"] for d in days))==length(days) || error("测试日集合")
    x=cat(
        (reduce(vcat, [permutedims(Float64.(row)) for row in d["values"]]) for d in days)...;
        dims = 3,
    )
    call(
        lib,
        :r6_trajectory_digest,
        "test",
        [d["id"] for d in days],
        x,
        m["test_protocol_sha256"],
    ) ==
    m["test_set_sha256"] ==
    raw["source_set_sha256"] || error("原始测试轨迹改变")
    policies=Dict{String,Any}()
    for scheme in m["protocol"]["schemes"]
        s=m["slots"][scheme]
        s["scheme"]==scheme || error("训练槽身份")
        if s["test_operation_defined"]
            p=call(lib, :R9ReservePolicy, TOML.parsefile(S.safe(frozen, s["policy_file"])))
            p.sha256==s["policy_sha256"] && p.operation_sha256==s["operation_sha256"] ||
                error("策略改变")
            policies[scheme]=p
        else
            s["status"]=="training_candidate_unavailable" || error("缺失策略状态")
        end
    end
    for (scheme, p) in policies
        owner=m["slots"][scheme]["compute_owner"]
        haskey(policies, owner) &&
        p.operation_sha256==policies[owner].operation_sha256 &&
        call(lib, :r9_operation_data, p.data)==call(lib, :r9_operation_data, policies[owner].data) ||
            error("不合法的共用操作")
    end
    (; m, lib, policies, days, x, hash = hashfile(joinpath(frozen, "manifest.toml")))
end

function day_identity(ctx, owner, i, got)
    got.policy.sha256==ctx.policies[owner].sha256 &&
    got.trajectory==ctx.x[:, :, i] &&
    got.result["trajectory_id"]==ctx.days[i]["id"] || error("原值不属于冻结日/操作")
    true
end

function day_bytes(ctx, owner, i, dir)
    m=TOML.parsefile(joinpath(dir, "files.toml"))
    Set(keys(m["files"]))==Set(["policy.toml", "trajectory.toml", "result.toml"]) &&
    Set(readdir(dir))==Set(["files.toml", "policy.toml", "trajectory.toml", "result.toml"]) ||
        error("逐日文件集合错误")
    for (f, h) in m["files"]
        hashfile(S.safe(dir, f))==h || error("逐日文件改变")
    end
    p=call(ctx.lib, :R9ReservePolicy, TOML.parsefile(joinpath(dir, "policy.toml")))
    r=TOML.parsefile(joinpath(dir, "result.toml"))
    raw=TOML.parsefile(joinpath(dir, "trajectory.toml"))
    raw["values"]==ctx.days[i]["values"] &&
    p.sha256==ctx.policies[owner].sha256 &&
    r["policy_sha256"]==p.sha256 &&
    r["operation_sha256"]==p.operation_sha256 &&
    r["trajectory_id"]==ctx.days[i]["id"] &&
    r["budget_sec"]==ctx.m["protocol"]["day_budget_sec"] &&
    r["source_hashes_at_solve"]==ctx.m["science_hashes"] || error("逐日身份不同")
    r
end

"""按原顺序执行最多limit个尚无记录的日子；重复调用只追加，完整失败记录也不重试。"""
function runbatch(frozen, runs; limit = 50)
    started=clock()
    1<=limit<=1000 || error("批次长度")
    ctx=openfreeze(frozen)
    hashfile(@__FILE__)==ctx.m["source_hashes"]["scripts/r9_reserve_evaluation.jl"] ||
        error("运行器已经改变；使用冻结的运行器和依赖，不能静默迁移")
    p=ctx.m["protocol"]
    attrs=p["solver"]
    attrs["name"]=="HiGHS" || error("求解器协议")
    optimizer=optimizer_with_attributes(HiGHS.Optimizer, (k=>v for (k, v) in attrs if k!="name")...)
    if !ispath(runs)
        mkpath(runs)
        toml(
            joinpath(runs, "identity.toml"),
            Dict("freeze_sha256"=>ctx.hash, "origin"=>"synthetic"),
        )
    end
    TOML.parsefile(joinpath(runs, "identity.toml"))["freeze_sha256"]==ctx.hash ||
        error("运行属于其他批次")
    owners=sort(unique(ctx.m["slots"][s]["compute_owner"] for s in keys(ctx.policies)))
    n=0
    setup=clock()-started
    for owner in owners, i in eachindex(ctx.days)
        dest=joinpath(runs, owner, ctx.days[i]["id"])
        if ispath(dest)
            day_bytes(ctx, owner, i, dest)
            continue
        end
        n>=limit && break
        # 一轮不允许并发写同一日；原子目录保存还会检查最终目标是否已被创建。
        daystart=clock()
        policy=ctx.policies[owner]
        r=call(
            ctx.lib,
            :evaluate_r9_reserve_day,
            policy,
            ctx.x[:, :, i];
            id = ctx.days[i]["id"],
            optimizer,
            budget_sec = p["day_budget_sec"],
        )
        call(ctx.lib, :save_r9_reserve_day, policy, ctx.x[:, :, i], r, dest)
        n+=1
        println(
            owner,
            " ",
            ctx.days[i]["id"],
            " status=",
            r["status"],
            " event=",
            r["validation"]["comfort_outcome"],
            " total_with_save_sec=",
            clock()-daystart,
        )
        flush(stdout)
        GC.gc()
    end
    mkpath(joinpath(runs, "batches"))
    toml(
        joinpath(runs, "batches", string(uuid4())*".toml"),
        Dict(
            "new_days"=>n,
            "setup_sec"=>setup,
            "elapsed_sec"=>clock()-started,
            "freeze_sha256"=>ctx.hash,
            "created_utc"=>string(now(UTC)),
        ),
    )
    println("Batch completed; new days=", n, " elapsed=", clock()-started)
end

"""只读重建所有已有日；缺失日继续算未知，缺失训练候选独立标记且不伪造日结果。"""
function check(frozen, runs = nothing; replay = true)
    ctx=openfreeze(frozen)
    runs===nothing && return ctx
    TOML.parsefile(joinpath(runs, "identity.toml"))["freeze_sha256"]==ctx.hash ||
        error("运行批次身份")
    count=0
    for owner in sort(unique(ctx.m["slots"][s]["compute_owner"] for s in keys(ctx.policies))),
        i in eachindex(ctx.days)

        dir=joinpath(runs, owner, ctx.days[i]["id"])
        ispath(dir) || continue
        if replay
            day_identity(ctx, owner, i, call(ctx.lib, :read_r9_reserve_day, dir))
        else
            day_bytes(ctx, owner, i, dir)
        end
        count+=1
    end
    println("Frozen inputs and ", count, " saved days checked; numerical replay=", replay)
    ctx
end

function main(args)
    if length(args)==5 && args[1]=="freeze"
        freeze(abspath.(args[2:5])...)
    elseif length(args) in (3, 4) && args[1]=="run"
        runbatch(
            abspath(args[2]),
            abspath(args[3]);
            limit = length(args)==4 ? parse(Int, args[4]) : 50,
        )
    elseif length(args) in (2, 3) && args[1]=="check"
        check(abspath(args[2]), length(args)==3 ? abspath(args[3]) : nothing)
    else
        error(
            "usage: freeze COMMON TRAINING_INPUT TRAINING_EVIDENCE NEW_FREEZE | run FREEZE RUNS [LIMIT] | check FREEZE [RUNS]",
        )
    end
end
end
if abspath(PROGRAM_FILE)==@__FILE__
    R9ReserveEvaluationStudy.main(ARGS)
end
