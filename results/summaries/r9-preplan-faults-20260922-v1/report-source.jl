# 独立故障评价只读封存：重算父计划、事件继承和原值，不调用任何优化器。
module R9PreplanFaultEvidence
using TOML, Dates
include("r9_preplan_diagnostic_evidence.jl")
const D=R9PreplanDiagnosticEvidence
const E=D.Evidence
const Old=E.Old
const Objects=E.Objects
const ROOT=dirname(@__DIR__)

function verify_files(dir)
    expected=TOML.parsefile(joinpath(dir, "files.toml"))["files"]
    actual=E.files(dir)
    delete!(actual, "files.toml")
    actual==expected || error("独立故障原值集合或字节改变")
    expected
end

"""
    make_table(input, baseline, parent, raw)

用冻结源码重算原4B和事件全开CHP1候选的逐故障恢复。关键失供单位MWh；
无候选的状态保持缺失，不用零值替代。先核验共同输入、故障、继承和固定流量，
再计算同一故障/表示下的差值。该差值不是单独启停因果效应，也不认证真实电热网。
"""
function make_table(input, baseline, parent, raw)
    ip=E.verify_input(input)
    be=E.verify_method(baseline, input, "penalty")
    D.verify_audit(parent, input)
    files=verify_files(raw)
    p=TOML.parsefile(joinpath(raw, "protocol.toml"))
    e=TOML.parsefile(joinpath(raw, "execution.toml"))
    p["schema"]=="r9-preplan-fault-evaluation-v1" &&
    !p["preplan_optimization_performed"] &&
    !p["whole_fault_claim"] &&
    p["physical_inputs_and_parent_values_unchanged"] || error("独立评价范围不符")
    p["input_manifest_sha256"]==E.hashfile(joinpath(input, "files.toml")) || error("输入清单不符")
    for name in
        ("normal.toml", "planning.toml", "penalty-spec.toml", "files.toml", "construction.toml")
        read(joinpath(raw, "input-"*name))==read(joinpath(input, name)) || error("输入副本改变")
    end
    for (copyname, name) in (
        ("parent-result.toml", "penalty_with_CHP1_event_on.toml"),
        ("parent-protocol.toml", "protocol.toml"),
        ("parent-audit.toml", "audit.toml"),
    )
        read(joinpath(raw, copyname))==read(joinpath(parent, name)) || error("父诊断副本改变")
    end
    p["parent_file_sha256"]==E.hashfile(joinpath(raw, "parent-result.toml")) ||
        error("父候选身份改变")
    im=TOML.parsefile(joinpath(input, "files.toml"))
    all(p["source_hashes"][k]==im["files"]["code/"*k] for k in im["code"]) &&
    all(get(files, "code/"*k, "")==h for (k, h) in p["source_hashes"]) ||
        error("独立评价科学源码不是原冻结")
    expected=[kind*"-"*id for id in ip["fault_ids"] for kind in ("aggregate", "detailed")]
    p["fault_ids"]==ip["fault_ids"] &&
    p["order"]==expected &&
    [z["stage"] for z in e["stages"]]==expected || error("阶段缺失或顺序改变")
    p["budget_sec"]==600.0 &&
    p["recovery_deadline_sec"]==540.0 &&
    p["stage_max_sec"]==60.0 &&
    p["substeps"]==ip["recovery_substeps"] &&
    e["budget_pass"]==(e["total_wall_sec"]<=p["budget_sec"]) &&
    !e["whole_fault_claim"] || error("预算或输运规则改变")
    bx=Old.frozen_read(joinpath(baseline, "primary"))
    c=bx.data.case
    c.normal.data==TOML.parsefile(joinpath(input, "normal.toml")) &&
    c.specification==TOML.parsefile(joinpath(input, "planning.toml")) || error("基准物理输入不同")
    lib=Base.invokelatest(getfield, bx.mod, :FrozenR9Preplan)
    call(sym, args...) = Base.invokelatest(Base.invokelatest(getfield, lib, sym), args...)
    spec=TOML.parsefile(joinpath(input, "penalty-spec.toml"))
    r=TOML.parsefile(joinpath(raw, "parent-result.toml"))
    q=call(:r7_planning_master_check, call(:r9_preplan_carrier, c, spec), r["master"])
    isequal(q, r["validation"]) && q["normal_pass"] && q["included_pass"] ||
        error("父计划原值回代失败")
    normal=r["master"]["normal"]
    r["run_id"]==p["parent_run_id"] && normal["run_id"]==p["normal_run_id"] ||
        error("父运行身份不符")
    event=call(:r7_planning_event, c, normal, 1)
    event.case.data==TOML.parsefile(joinpath(raw, "event.toml")) &&
    event.evidence==TOML.parsefile(joinpath(raw, "inheritance.toml")) || error("事件继承不符")
    ev=only(c.specification["events"])
    win=ev["event_start"]:(ev["event_start"]+ev["periods"]-1)
    all(abs(v-1)<=1e-6 for v in call(:r7_unpack, normal["chp_values"]["CHP1"], "u_CHP")[win]) ||
        error("声明的CHP1事件全开不成立")
    baseevent=call(:r7_planning_event, c, bx.data.result["master"]["normal"], 1)
    baseevent.case.data==TOML.parsefile(joinpath(baseline, "event.toml")) || error("基准继承不同")
    construction=TOML.parsefile(joinpath(input, "construction.toml"))
    rows=NamedTuple[]
    for z in e["stages"]
        label=z["stage"]
        kind, id=split(label, '-'; limit = 2)
        bs=only(filter(s->s["stage"]==label, be["stages"]))
        bs["attempted"] || error("基准对应故障没有运行")
        old=Old.frozen_read(joinpath(baseline, label)).data
        old.case.data==baseevent.case.data &&
        old.result["run_id"]==bs["run_id"] &&
        old.result["fault"]==construction["pilot_faults"][id] || error("基准原值与故障不符")
        base_loss=get(old.validation, "loss_MWh", NaN)
        loss, lower, gap=NaN, NaN, NaN
        pass, exact, optimal=false, false, false
        run_id=""
        if z["attempted"]
            0<z["budget_sec"]<=p["stage_max_sec"] || error("阶段预算改变")
            y=Old.frozen_read(joinpath(raw, label)).data
            y.case.data==event.case.data &&
            y.result["fault"]==construction["pilot_faults"][id] &&
            y.result["run_id"]==z["run_id"] &&
            y.result["status"]==z["status"] &&
            y.validation["model_pass"]==z["model_pass"] &&
            isequal(get(y.validation, "loss_MWh", NaN), z["loss_MWh"]) || error("新恢复原值不符")
            if kind=="detailed"
                y.spec==TOML.parsefile(joinpath(raw, "transport-spec.toml")) &&
                y.spec["profiles"]==event.evidence["initial_pipe_profiles"] &&
                y.spec["substeps"]==p["substeps"] &&
                !y.spec["uniform_assumption"] || error("逐管输运规格/完整空间状态不符")
                h=c.normal.data["heat"]
                flows=Dict(
                    "m_pipe"=>reduce(
                        vcat,
                        [permutedims(v["normal_flow_kg_s"][win]) for v in h["pipes"]],
                    ),
                    "m_source"=>reduce(vcat, [permutedims(v[win]) for v in h["source_flow_kg_s"]]),
                    "m_load"=>reduce(vcat, [permutedims(v[win]) for v in h["load_flow_kg_s"]]),
                )
                all(Old.unpack(y.spec["flow_schedule"], k)==v for (k, v) in flows) ||
                    error("恢复固定流量改变")
            end
            pass=y.validation["model_pass"]
            loss=get(y.validation, "loss_MWh", NaN)
            lower=get(y.result, "lower_bound_MWh", NaN)
            gap=get(y.validation, "relative_gap", NaN)
            optimal=get(
                y.validation,
                kind=="aggregate" ? "optimality_pass" : "conditional_optimality_pass",
                false,
            )
            exact=get(y.validation, "exchange_exact_pass", false)
            run_id=y.result["run_id"]
        else
            ispath(joinpath(raw, label)) && error("未执行阶段存在原值")
        end
        push!(
            rows,
            (;
                stage = label,
                run_id,
                status = z["status"],
                model_pass = pass,
                baseline_run_id = old.result["run_id"],
                baseline_model_pass = old.validation["model_pass"],
                baseline_loss_MWh = base_loss,
                loss_MWh = loss,
                lower_bound_MWh = lower,
                relative_gap = gap,
                conditional_optimality_pass = optimal,
                loss_reduction_MWh = pass && old.validation["model_pass"] ? base_loss-loss : NaN,
                critical_limit_MWh = ip["loss_limit_MWh"],
                critical_limit_pass = pass && loss<=ip["loss_limit_MWh"],
                aggregate_exact_exchange_pass = exact,
                aggregate_exact_exchange_applicable = kind=="aggregate",
                normal_cost_CNY = q["cost"],
                baseline_normal_cost_CNY = bx.data.validation["normal_cost"],
                parent_run_id = p["parent_run_id"],
            ),
        )
    end
    Objects.csvbytes(rows)
end

function freeze(input, baseline, parent, raw, out)
    ispath(out) && error("不覆盖独立故障证据")
    table=make_table(input, baseline, parent, raw)
    stage=out*".writing"
    ispath(stage) && error("未完成封存已存在")
    mkpath(joinpath(stage, "objects"))
    index=Dict(
        "schema"=>"r9-preplan-fault-evidence-v1",
        "utc"=>string(now(UTC)),
        "input"=>Objects.pack(stage, input),
        "baseline"=>Objects.pack(stage, baseline),
        "parent"=>Objects.pack(stage, parent),
        "raw"=>Objects.pack(stage, raw),
        "optimization_performed"=>false,
        "whole_fault_certificate"=>false,
        "origin"=>"declared replacement inputs; inherited frozen planning candidates",
    )
    E.toml(joinpath(stage, "index.toml"), index)
    write(joinpath(stage, "comparison.csv"), table)
    cp(@__FILE__, joinpath(stage, "report-source.jl"))
    for name in (
        "r9_preplan_diagnostic_evidence.jl",
        "r9_preplan_evidence.jl",
        "r9_resilience_evidence.jl",
        "r9_fixed_evidence.jl",
    )
        cp(joinpath(@__DIR__, name), joinpath(stage, name))
    end
    E.toml(joinpath(stage, "artifacts.toml"), Dict("files"=>E.files(stage)))
    mv(stage, out)
    println("Independent fault evidence frozen: ", relpath(out, ROOT))
end

function check(out; replay = false)
    a=TOML.parsefile(joinpath(out, "artifacts.toml"))["files"]
    actual=E.files(out)
    delete!(actual, "artifacts.toml")
    actual==a || error("独立故障封存字节或集合改变")
    x=TOML.parsefile(joinpath(out, "index.toml"))
    x["schema"]=="r9-preplan-fault-evidence-v1" &&
    !x["optimization_performed"] &&
    !x["whole_fault_certificate"] || error("独立故障封存范围错误")
    if replay
        temp=mktempdir(joinpath(ROOT, "tmp"); prefix = "r9-preplan-faults-", cleanup = false)
        names=("input", "baseline", "parent", "raw")
        for name in names
            Old.extract(out, x[name], joinpath(temp, name))
        end
        m=Module(gensym(:FrozenPreplanFaults))
        Base.include(m, joinpath(out, "report-source.jl"))
        lib=Base.invokelatest(getfield, m, :R9PreplanFaultEvidence)
        fn=Base.invokelatest(getfield, lib, :make_table)
        bytes=Base.invokelatest(fn, (joinpath(temp, name) for name in names)...)
        bytes==read(joinpath(out, "comparison.csv")) || error("独立故障表重算不同")
        println("Independent fault frozen-source replay passed: ", relpath(temp, ROOT))
    end
    println("Independent fault evidence hashes passed: ", length(a))
    true
end
end

if abspath(PROGRAM_FILE)==@__FILE__
    if length(ARGS)==6 && ARGS[1]=="freeze"
        R9PreplanFaultEvidence.freeze(abspath.(ARGS[2:6])...)
    elseif length(ARGS) in (2, 3) && ARGS[1]=="check" && (length(ARGS)==2 || ARGS[3]=="--replay")
        R9PreplanFaultEvidence.check(abspath(ARGS[2]); replay = length(ARGS)==3)
    else
        error(
            "usage: r9_preplan_fault_evidence.jl freeze INPUT BASELINE PARENT RAW NEW_EVIDENCE | check EVIDENCE [--replay]",
        )
    end
end
