include("r6_study.jl")

# 只允许这一项输入字节完全等价的哈希实现修正；不接纳模型、求解器或规则的变化。
const R6_HASH_OLD="\"parent_result_sha256\"=>bytes2hex(sha256(r5_market_text(r))),"
const R6_HASH_NEW="\"parent_result_sha256\"=>bytes2hex(sha256(IOBuffer(r5_market_text(r)))),"

function r6_continuation_source_check(parent, current)
    old=TOML.parsefile(joinpath(parent, "freeze.toml"))
    new=TOML.parsefile(joinpath(current, "freeze.toml"))
    for dir in (parent, current)
        r6_study_hash(joinpath(dir, "freeze.toml"))==strip(
            read(joinpath(dir, "freeze.sha256"), String),
        ) || error("冻结清单改变")
    end
    Set(keys(old["sources"]))==Set(keys(new["sources"])) || error("续接源码范围不同")
    changed=sort([p for p in keys(old["sources"]) if old["sources"][p]!=new["sources"][p]])
    changed==["src/core/r6_evaluation.jl"] || error("不是单一哈希实现修正")
    texts=String[]
    for (dir, m) in ((parent, old), (current, new))
        archive=read(joinpath(dir, "source.tar"))
        bytes2hex(sha256(archive))==m["archive_sha256"] || error("源码归档改变")
        r6_study_check_archive(archive, m["sources"])
        mktempdir() do temp
            Tar.extract(IOBuffer(archive), temp)
            push!(texts, read(joinpath(temp, only(changed)), String))
        end
    end
    count(R6_HASH_OLD, texts[1])==1 || error("父源码哈希调用位置不唯一")
    replace(texts[1], R6_HASH_OLD=>R6_HASH_NEW)==texts[2] ||
        error("除已声明UTF-8哈希载体外还有源码变化")
    for field in (
        "spec",
        "spec_sha256",
        "physical_sha256",
        "protocol_sha256",
        "cases",
        "sets",
        "stress_sha256",
        "data_manifest_sha256",
    )
        old[field]==new[field] || error("续接改变了输入或规则：$field")
    end
    (; old, new)
end

function continue_r6_study(parent, current)
    ispath(joinpath(current, "continuation.toml")) && error("不覆盖已记录的续接")
    audit=r6_continuation_source_check(parent, current)
    ctx=r6_study_open(current; execution = true)
    reused=Dict{String,Any}()
    for c in r6_study_candidates(ctx.spec)
        id=c["id"]
        source=joinpath(parent, "training", id)
        isdir(source) || continue
        dest=joinpath(current, "training", id)
        ispath(dest) && error("续接目标已有结果，不覆盖")
        # 旧原值和原提交/源码快照完整保留；先读旧文件核验，不重新优化。
        x=r6_study_training_record(parent, id, ctx)
        prior=joinpath(parent, "training-records", id*".toml")
        if isfile(prior)
            isequal(TOML.parsefile(prior), x.record) || error("续接改变旧训练摘要")
        end
        policy=joinpath(parent, "policies", id*".toml")
        if isfile(policy)
            x.policy!==nothing && isequal(TOML.parsefile(policy), x.policy.data) ||
                error("续接改变旧策略")
        end
        mkpath(dirname(dest))
        cp(source, dest)
        PaperRebuild.r5_market_file_inventory(source)==PaperRebuild.r5_market_file_inventory(
            dest,
        ) || error("复制清单不同")
        for rel in PaperRebuild.r5_market_file_inventory(source)
            r6_study_hash(joinpath(source, rel))==r6_study_hash(joinpath(dest, rel)) ||
                error("复制原值不同")
        end
        r6_study_new(joinpath(current, "training-records", id*".toml"), x.record)
        x.policy===nothing || r6_study_new(joinpath(current, "policies", id*".toml"), x.policy.data)
        reused[id]=Dict(
            "run_id"=>x.record["run_id"],
            "result_sha256"=>x.record["result_sha256"],
            "candidate_accepted"=>x.record["candidate_accepted"],
            "cost_complete"=>x.record["cost_optimization_complete"],
            "policy_identical_to_parent"=>isfile(policy),
            "optimized_again"=>false,
        )
        println(
            "REUSED ",
            id,
            " accepted=",
            x.record["candidate_accepted"],
            " without optimization.",
        )
        flush(stdout)
    end
    r6_study_new(
        joinpath(current, "continuation.toml"),
        Dict(
            "schema"=>"r6-byte-identical-hash-continuation-v1",
            "reason"=>"confirmed_quadratic_string_digest_after_saved_optimization",
            "parent_freeze_sha256"=>r6_study_hash(joinpath(parent, "freeze.toml")),
            "current_freeze_sha256"=>r6_study_hash(joinpath(current, "freeze.toml")),
            "parent_source_commit"=>audit.old["source_commit"],
            "current_source_commit"=>audit.new["source_commit"],
            "change"=>"SHA256_String_to_UTF8_IOBuffer_only",
            "reused"=>reused,
            "model_and_rules_unchanged"=>true,
        ),
    )
    println("Continuation recorded; unattempted candidates keep the original budgets and rules.")
end

if abspath(PROGRAM_FILE)==(@__FILE__)
    length(ARGS)==2 || error("usage: continue_r6_study.jl <parent-batch> <new-frozen-batch>")
    continue_r6_study(ARGS...)
end
