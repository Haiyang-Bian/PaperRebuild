include("r5_strategic_setup.jl")
include("r6_study_io.jl")

function train_r6_study(directory)
    ctx=r6_study_open(directory; execution = true)
    optimizer=try
        r6_study_solver(ctx.spec, "gurobi")
    catch err
        # 缺许可/依赖保留为各配置的执行失败，不伪造数学不可行或切换模型。
        failure=err
        ()->throw(failure)
    end
    oracle=r6_study_solver(ctx.spec, "highs")
    for entry in r6_study_candidates(ctx.spec)
        id=entry["id"]
        path=joinpath(directory, "training", id)
        if !ispath(path)
            c=R5StrategicCase(TOML.parsefile(joinpath(directory, "inputs", id*".toml")))
            println("BEGIN TRAIN ", id, " case=", c.sha256)
            flush(stdout)
            r=Base.invokelatest(
                solve_r6_training,
                c;
                optimizer,
                oracle_optimizer = oracle,
                budget_sec = ctx.spec.data["training_budget_sec"],
            )
            save_r5_strategic_run(c, r, path)
        end
        # 续读已经封存的结果，不因超时或失败再次求解。未封存的部分目录须单独审计。
        x=r6_study_training_record(directory, id, ctx)
        recordpath=joinpath(directory, "training-records", id*".toml")
        if isfile(recordpath)
            isequal(TOML.parsefile(recordpath), x.record) || error("训练摘要改变")
        else
            r6_study_new(recordpath, x.record)
        end
        if x.policy!==nothing
            policypath=joinpath(directory, "policies", id*".toml")
            isfile(policypath) ?
            (isequal(TOML.parsefile(policypath), x.policy.data) || error("已保存策略改变")) :
            r6_study_new(policypath, x.policy.data)
        end
        r6_study_assert_sources(ctx.root, ctx.manifest)
        println(
            "END TRAIN ",
            id,
            " status=",
            x.record["status"],
            " accepted=",
            x.record["candidate_accepted"],
            " complete=",
            x.record["cost_optimization_complete"],
            " cost=",
            x.record["training_objective_USD"],
            " seconds=",
            x.record["elapsed_sec"],
        )
        flush(stdout)
    end
end

function r6_study_all_training(directory, ctx)
    ids=[x["id"] for x in r6_study_candidates(ctx.spec)]
    all(isfile(joinpath(directory, "training-records", id*".toml")) for id in ids) ||
        error("训练记录未完成")
    trained=Dict(id=>r6_study_training_record(directory, id, ctx) for id in ids)
    for id in ids
        isequal(
            TOML.parsefile(joinpath(directory, "training-records", id*".toml")),
            trained[id].record,
        ) || error("训练摘要与独立重读不一致")
    end
    trained
end

function r6_study_selection(directory, ctx, trained)
    path=joinpath(directory, "selection.toml")
    x=TOML.parsefile(path)
    r6_study_hash(path)==strip(read(joinpath(directory, "selection.sha256"), String)) ||
        error("测试前选择被更改")
    records=Dict(
        c["id"]=>r6_study_checked_summary(directory, "validation", c, ctx, trained[c["id"]]) for
        c in r6_study_candidates(ctx.spec)
    )
    isequal(x, select_r6_methods(ctx.spec, records)) || error("锁定选择不是冻结验证规则的结果")
    x
end

function evaluate_r6_study(directory, split)
    split in ("validation", "test", "stress") || error("只能评价冻结验证、测试或压力分组")
    ctx=r6_study_open(directory; execution = true)
    trained=r6_study_all_training(directory, ctx)
    candidates=r6_study_candidates(ctx.spec)
    if split in ("test", "stress")
        chosen=r6_study_selection(directory, ctx, trained)
        ids=Set(x["candidate_id"] for x in chosen["selected"])
        candidates=filter(c->c["id"] in ids, candidates)
    else
        isfile(joinpath(directory, "selection.toml")) && error("选择已锁定，验证阶段只允许只读核验")
    end
    s=r6_study_set(ctx, split)
    optimizer=r6_study_solver(ctx.spec, "highs")
    for candidate in candidates
        id=candidate["id"]
        folder=joinpath(directory, split, id)
        summarypath=joinpath(folder, "summary.toml")
        policy=trained[id].policy
        vals=Dict{String,Any}[]
        hashes=Dict{String,String}()
        if policy===nothing
            append!(vals, [r6_study_unknown() for _ in s.ids])
        else
            for (i, dayid) in enumerate(s.ids)
                path=joinpath(folder, "days", dayid*".toml")
                v=s.values[:, :, i]
                if !isfile(path)
                    # 每天只有一次声明的分支求解，未完成也写原值；没有诊断替换或择优重试。
                    r=evaluate_r6_policy_day(
                        policy,
                        v;
                        id = dayid,
                        optimizer,
                        budget_sec = ctx.spec.data["day_budget_sec"],
                    )
                    compact=r6_study_compact(r["validation"])
                    delete!(r, "validation")
                    w=Dict(
                        "schema"=>"r6-study-day-v1",
                        "split"=>split,
                        "set_sha256"=>s.sha256,
                        "candidate_id"=>id,
                        "result"=>r,
                        "validation"=>compact,
                    )
                    r6_study_new(path, w)
                end
                w=TOML.parsefile(path)
                w["split"]==split&&w["set_sha256"]==s.sha256&&w["candidate_id"]==id ||
                    error("跨分组或跨策略日记录")
                x=r6_study_day_read(path, policy, v)
                push!(vals, x.validation)
                hashes[dayid]=r6_study_hash(path)
                if i%25==0 || i==length(s.ids)
                    println(
                        "DAY ",
                        split,
                        " ",
                        id,
                        " ",
                        i,
                        "/",
                        length(s.ids),
                        " last=",
                        x.validation["comfort_outcome"],
                    )
                    flush(stdout)
                    r6_study_assert_sources(ctx.root, ctx.manifest)
                end
            end
        end
        record=Dict(
            "schema"=>"r6-split-candidate-v1",
            "candidate"=>candidate,
            "split"=>split,
            "set_sha256"=>s.sha256,
            "training_result_sha256"=>trained[id].record["result_sha256"],
            "training_candidate_accepted"=>policy!==nothing,
            "days"=>hashes,
            "summary"=>r6_study_summary(ctx, split, s, vals),
        )
        if isfile(summarypath)
            isequal(TOML.parsefile(summarypath), record) || error("已完成分组记录改变")
        else
            r6_study_new(summarypath, record)
        end
        v=record["summary"]
        if split=="stress"
            println("END stress ", id, " four deterministic outcomes saved; no probability claim.")
            flush(stdout)
            continue
        end
        println(
            "END ",
            split,
            " ",
            id,
            " risk=",
            v["risk"]["status"],
            " unknown=",
            v["risk"]["unknown"],
            " mean=",
            v["mean_net_cost_USD"],
        )
        flush(stdout)
    end
end

function check_r6_study(directory)
    ctx=r6_study_open(directory; execution = true)
    candidates=r6_study_candidates(ctx.spec)
    training=Dict{String,Any}()
    for c in candidates
        id=c["id"]
        path=joinpath(directory, "training-records", id*".toml")
        isfile(path) || continue
        x=r6_study_training_record(directory, id, ctx)
        isequal(TOML.parsefile(path), x.record) || error("训练摘要被修改")
        training[id]=x
    end
    counts=Dict(split=>0 for split in ("validation", "test", "stress"))
    locked=isfile(joinpath(directory, "selection.toml"))
    chosen=locked ? r6_study_selection(directory, ctx, training) : nothing
    for split in keys(counts), c in candidates
        path=joinpath(directory, split, c["id"], "summary.toml")
        isfile(path) || continue
        if split!="validation"
            locked || error("参数锁定前出现测试或压力结果")
            c["id"] in [s["candidate_id"] for s in chosen["selected"]] || error("测试使用未选策略")
        end
        r6_study_checked_summary(directory, split, c, ctx, training[c["id"]])
        counts[split]+=1
    end
    complete=length(training)==14&&counts["validation"]==14&&counts["test"]==6&&counts["stress"]==6
    println(
        "Verified frozen batch: training=",
        length(training),
        " summaries=",
        counts,
        " complete=",
        complete,
    )
    (; training = length(training), counts, complete)
end

function select_r6_study(directory)
    ctx=r6_study_open(directory; execution = true)
    trained=r6_study_all_training(directory, ctx)
    ispath(joinpath(directory, "selection.toml")) && error("不覆盖已锁定选择")
    records=Dict{String,Any}()
    for c in r6_study_candidates(ctx.spec)
        records[c["id"]]=r6_study_checked_summary(directory, "validation", c, ctx, trained[c["id"]])
    end
    selected=select_r6_methods(ctx.spec, records)
    r6_study_new(joinpath(directory, "selection.toml"), selected)
    write(
        joinpath(directory, "selection.sha256"),
        r6_study_hash(joinpath(directory, "selection.toml"))*"\n",
    )
    println("Six policies locked before test; validation eligibility retained separately.")
end

if abspath(PROGRAM_FILE)==(@__FILE__)
    length(ARGS)==2 || error(
        "usage: r6_study.jl freeze|train|validation|select|test|stress|check <study-directory>",
    )
    action, dir=ARGS
    action=="freeze" ? freeze_r6_study(dir) :
    action=="train" ? train_r6_study(dir) :
    action in ("validation", "test", "stress") ? evaluate_r6_study(dir, action) :
    action=="check" ? check_r6_study(dir) :
    action=="select" ? select_r6_study(dir) : error("未知正式研究操作")
end
