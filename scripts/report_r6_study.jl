include("r6_study.jl")
include("r6_study_tables.jl")

const R6_REPORT_SCRIPTS=["scripts/report_r6_study.jl", "scripts/r6_study_tables.jl"]

function r6_report_path(dir, rel)
    isabspath(rel)||occursin(':', rel)||occursin('\\', rel)||".." in split(rel, '/') ?
    error("报告来源须为仓库内相对路径") : joinpath(dir, split(rel, '/')...)
end

# 只读快照绑定已完成记录。报告生成后新增的其他运行不会改写这份历史快照。
function r6_study_report_data(directory; snapshot = nothing)
    ctx=r6_study_open(directory; execution = true)
    evidence=Dict{String,String}()
    visible(rel) =
        snapshot===nothing ? isfile(r6_report_path(directory, rel)) : haskey(snapshot, rel)
    function add(rel)
        h=r6_study_hash(r6_report_path(directory, rel))
        snapshot===nothing || get(snapshot, rel, nothing)==h || error("报告来源被更改：$rel")
        evidence[rel]=h
    end
    foreach(add, ["freeze.toml", "freeze.sha256", "source.tar"])
    candidates=r6_study_candidates(ctx.spec)
    trained=Dict{String,Any}()
    records=Dict{Tuple{String,String},Any}()
    counts=Dict(k=>0 for k in ("training", "validation", "test", "stress"))
    tables=Dict(k=>NamedTuple[] for k in ("training", "risk-cost", "days", "stress", "paired-cost"))
    for c in candidates
        id=c["id"]
        rel="training-records/$id.toml"
        if visible(rel)
            add(rel)
            x=r6_study_training_record(directory, id, ctx)
            isequal(TOML.parsefile(joinpath(directory, rel)), x.record) || error("训练摘要不一致")
            trained[id]=x
            foreach(
                add,
                ["training/$id/hashes.toml", "training/$id/result.toml", "training/$id/case.toml"],
            )
            if x.policy!==nothing
                path="policies/$id.toml"
                add(path)
                isequal(TOML.parsefile(joinpath(directory, path)), x.policy.data) ||
                    error("冻结策略不同")
            end
            counts["training"]+=1
        end
        push!(
            tables["training"],
            r6_study_training_row(c, haskey(trained, id) ? trained[id].record : nothing),
        )
    end
    selected=Dict{String,Any}[]
    for split in ("validation", "test", "stress")
        for c in candidates
            id=c["id"]
            rel="$split/$id/summary.toml"
            visible(rel) || continue
            haskey(trained, id) || error("分组证据缺少已封存训练")
            split=="validation" ||
                id in [x["candidate_id"] for x in selected] ||
                error("测试策略未锁定")
            add(rel)
            x=r6_study_checked_summary(directory, split, c, ctx, trained[id])
            records[(split, id)]=x
            counts[split]+=1
            s=r6_study_set(ctx, split)
            for day in s.ids
                if trained[id].policy===nothing
                    v, r=r6_study_unknown(), nothing
                else
                    rel="$split/$id/days/$day.toml"
                    add(rel)
                    w=TOML.parsefile(joinpath(directory, rel))
                    v, r=w["validation"], w["result"]
                end
                table=split=="stress" ? "stress" : "days"
                push!(tables[table], r6_study_day_row(split, c, day, v, r))
            end
        end
        if split=="validation" && visible("selection.toml")
            counts["validation"]==14 || error("完整验证前锁定选择")
            add("selection.toml")
            add("selection.sha256")
            evidence["selection.toml"]==strip(
                read(joinpath(directory, "selection.sha256"), String),
            ) || error("选择哈希错误")
            locked=TOML.parsefile(joinpath(directory, "selection.toml"))
            expected=select_r6_methods(
                ctx.spec,
                Dict(c["id"]=>records[(split, c["id"])] for c in candidates),
            )
            isequal(locked, expected) || error("选择与数值重验后的验证集不一致")
            selected=locked["selected"]
        end
    end
    for split in ("validation", "test"), c in candidates
        split=="validation" || c["id"] in [x["candidate_id"] for x in selected] || continue
        x=get(records, (split, c["id"]), nothing)
        push!(
            tables["risk-cost"],
            r6_study_summary_row(split, c, x===nothing ? nothing : x["summary"], selected),
        )
    end
    if counts["test"]==6
        tables["paired-cost"]=r6_study_pair_table(
            tables["days"],
            ctx.spec.data["methods"],
            ctx.data.protocol.data["statistics"],
        )
    end
    complete=counts==Dict("training"=>14, "validation"=>14, "test"=>6, "stress"=>6)
    # 末次核对防止并行会话在表格计算期间改写已读证据。新文件可以追加。
    for (rel, h) in evidence
        r6_study_hash(r6_report_path(directory, rel))==h || error("报告计算期间来源改变")
    end
    snapshot===nothing || evidence==snapshot || error("报告快照清单含有遗漏或未知文件")
    r6_study_assert_sources(ctx.root, ctx.manifest)
    (; ctx, tables, evidence, counts, complete)
end

function report_r6_study(source, output; partial = false)
    ispath(output) && error("不覆盖已有正式或进度报告")
    x=r6_study_report_data(source)
    partial||x.complete || error("正式结果尚未全部封存；进度快照须显式使用snapshot")
    files=r6_study_table_bytes(x.tables)
    meta=Dict(
        "schema"=>"r6-study-report-v1",
        "origin"=>"synthetic",
        "status"=>x.complete ? "records_complete_not_automatic_scientific_pass" :
                  "partial_progress_only",
        "complete"=>x.complete,
        "counts"=>x.counts,
        "snapshot"=>x.evidence,
        "freeze_sha256"=>x.evidence["freeze.toml"],
        "source_commit"=>x.ctx.manifest["source_commit"],
        "reporter_hashes"=>Dict(
            p=>r6_study_hash(joinpath(x.ctx.root, p)) for p in R6_REPORT_SCRIPTS
        ),
        "tables"=>Dict(p=>bytes2hex(sha256(bytes)) for (p, bytes) in files),
        "scope"=>"local_numeric_replay_requires_raw_batch_and_frozen_scientific_sources",
        "test_claim"=>"DRJCC_joint_comfort_on_declared_synthetic_distribution",
        "cost_scope"=>"IES_net_payment_not_social_resource_cost",
        "stress_scope"=>"deterministic_cases_no_probability_claim",
    )
    mkpath(output)
    for (p, bytes) in files
        write(joinpath(output, p), bytes)
    end
    r6_study_new(joinpath(output, "report.toml"), meta)
    write(joinpath(output, "report.sha256"), r6_study_hash(joinpath(output, "report.toml"))*"\n")
    println("Saved verified R6 report: ", meta["status"], " counts=", x.counts)
end

function check_r6_study_report(source, report)
    meta=TOML.parsefile(joinpath(report, "report.toml"))
    meta["schema"]=="r6-study-report-v1" || error("报告版本错误")
    r6_study_hash(joinpath(report, "report.toml"))==strip(
        read(joinpath(report, "report.sha256"), String),
    ) || error("报告清单改变")
    root=normpath(joinpath(@__DIR__, ".."))
    Set(keys(meta["reporter_hashes"]))==Set(R6_REPORT_SCRIPTS) || error("报告程序清单改变")
    for (p, h) in meta["reporter_hashes"]
        r6_study_hash(joinpath(root, p))==h || error("报告生成器版本不同")
    end
    inventory=PaperRebuild.r5_market_file_inventory(report)
    Set(inventory)==union(Set(keys(meta["tables"])), Set(["report.toml", "report.sha256"])) ||
        error("报告文件清单不同")
    x=r6_study_report_data(source; snapshot = meta["snapshot"])
    x.complete==meta["complete"] && x.counts==meta["counts"] || error("报告完成状态与证据不符")
    meta["freeze_sha256"]==x.evidence["freeze.toml"] || error("报告不是对应冻结批次")
    meta["source_commit"]==x.ctx.manifest["source_commit"] && meta["origin"]=="synthetic" ||
        error("报告源码或输入来源声明错误")
    expected_status=x.complete ? "records_complete_not_automatic_scientific_pass" :
                    "partial_progress_only"
    meta["status"]==expected_status &&
    meta["scope"]=="local_numeric_replay_requires_raw_batch_and_frozen_scientific_sources" &&
    meta["test_claim"]=="DRJCC_joint_comfort_on_declared_synthetic_distribution" &&
    meta["cost_scope"]=="IES_net_payment_not_social_resource_cost" &&
    meta["stress_scope"]=="deterministic_cases_no_probability_claim" || error("报告扩大了证据范围")
    files=r6_study_table_bytes(x.tables)
    Set(keys(files))==Set(keys(meta["tables"])) || error("生成表清单不一致")
    for (p, bytes) in files
        bytes==read(joinpath(report, p)) && bytes2hex(sha256(bytes))==meta["tables"][p] ||
            error("表格未通过数值重读：$p")
    end
    println("R6 report and every recorded parent/day independently replayed; no optimization.")
end

if abspath(PROGRAM_FILE)==(@__FILE__)
    length(ARGS)==3 || error("usage: report_r6_study.jl create|snapshot|check <raw-batch> <report>")
    action, source, output=ARGS
    action=="check" ? check_r6_study_report(source, output) :
    action in ("create", "snapshot") ?
    report_r6_study(source, output; partial = action=="snapshot") : error("未知报告操作")
end
