# 独立诊断的原值/源码封存与移位重验；不改变正式方案的状态，不调用优化器。
module R9PreplanDiagnosticEvidence
using TOML, SHA, Dates
include("r9_preplan_evidence.jl")
const Evidence = R9PreplanEvidence
const Old = Evidence.Old
const Objects = Evidence.Objects
const ROOT = dirname(@__DIR__)

function verify_audit(dir, input)
    a = TOML.parsefile(joinpath(dir, "audit.toml"))
    p = TOML.parsefile(joinpath(dir, "protocol.toml"))
    actual = Evidence.files(dir)
    delete!(actual, "audit.toml")
    actual == a["files"] || error("诊断文件集合或字节改变")
    p["input_manifest_sha256"] == Evidence.hashfile(joinpath(input, "files.toml")) ||
        error("诊断输入改变")
    a["budget_pass"] == (a["total_wall_sec"] <= p["budget_sec"]) && !a["whole_fault_claim"] ||
        error("诊断范围或预算错误")
    f = TOML.parsefile(joinpath(input, "files.toml"))
    all(get(p["source_hashes"], k, "") == f["files"]["code/"*k] for k in f["code"]) ||
        error("诊断科学源码未匹配原冻结")
    all(get(actual, "code/" * k, "") == h for (k, h) in p["source_hashes"]) ||
        error("诊断源码副本不符")
    (; audit = a, protocol = p)
end

function row(
    label,
    status;
    model_pass = false,
    normal_cost = NaN,
    loss = NaN,
    objective = NaN,
    bound = NaN,
    units = "none",
    on_steps = NaN,
    scope = "",
    bound_pass = false,
)
    (;
        diagnostic = label,
        status,
        model_pass,
        normal_cost_CNY = normal_cost,
        selected_worst_loss_MWh = loss,
        solver_objective = objective,
        objective_lower_bound = bound,
        objective_units = units,
        CHP1_event_on_steps = on_steps,
        bound_pass,
        scope,
    )
end

function make_table(input, commitment, floor)
    Evidence.verify_input(input)
    ca = verify_audit(commitment, input)
    fa = verify_audit(floor, input)
    ca.protocol["schema"] == "r9-preplan-commitment-audit-v1" &&
    fa.protocol["schema"] == "r9-preplan-loss-audit-v1" || error("诊断协议版本不同")
    x = Old.frozen_read(joinpath(commitment, "threshold-clarified"))
    c = x.data.case
    c.normal.data == TOML.parsefile(joinpath(input, "normal.toml")) &&
    c.specification == TOML.parsefile(joinpath(input, "planning.toml")) || error("消歧案例改变")
    s = TOML.parsefile(joinpath(input, "penalty-spec.toml"))
    lib = Base.invokelatest(getfield, x.mod, :FrozenR9Preplan)
    call(sym, args...) = Base.invokelatest(Base.invokelatest(getfield, lib, sym), args...)
    carrier = call(:r9_preplan_carrier, c, s)
    ev = only(c.specification["events"])
    win = ev["event_start"]:(ev["event_start"]+ev["periods"]-1)
    rows = [
        row(
            "threshold_DualReductions_0",
            x.data.result["status"];
            model_pass = x.data.validation["model_pass"],
            scope = "separate same-model solve; original ambiguous status retained",
        ),
    ]
    n = TOML.parsefile(joinpath(commitment, "max-on.toml"))
    if haskey(n, "normal")
        q = call(:validate_r7_normal, c.normal, n["normal"])
        isequal(q, n["normal_validation"]) || error("正常开机诊断回代不同")
        u = call(:r7_unpack, n["normal"]["chp_values"]["CHP1"], "u_CHP")
        on = sum(u[win])
        on == n["objective_replay"] == n["on_steps"] || error("开机目标不符")
        push!(
            rows,
            row(
                "normal_maximum_CHP1_event_on",
                n["status"];
                model_pass = q["model_pass"] && q["pipe_reference_pass"],
                normal_cost = q["cost"],
                objective = on,
                on_steps = on,
                units = "steps",
                scope = "normal feasibility only; no recovery or minimum-cost certificate",
            ),
        )
    else
        push!(rows, row("normal_maximum_CHP1_event_on", n["status"]; scope = "no normal candidate"))
    end
    for kind in fa.protocol["order"]
        r = TOML.parsefile(joinpath(floor, kind * ".toml"))
        r["source_hashes"] == fa.protocol["source_hashes"] &&
        r["input_manifest_sha256"] == fa.protocol["input_manifest_sha256"] ||
            error("失供诊断身份不同")
        if !haskey(r, "master")
            push!(rows, row(kind, r["status"]; scope = "no candidate"))
            continue
        end
        m = r["master"]
        isequal(m["included"], s["pairs"]) || error("失供诊断故障子集改变")
        q = call(:r7_planning_master_check, carrier, m)
        isequal(q, r["validation"]) || error("诊断正常/继承/恢复见证回代不同")
        z = r["epigraph_MWh"]
        caps = call(:r8_loss_caps, c)
        ep =
            length(z) == length(caps) &&
            all(isfinite, z) &&
            all(
                -1e-6 * (1 + max(1, cap)) <= v <= cap + 1e-6 * (1 + max(1, cap)) for
                (v, cap) in zip(z, caps)
            ) &&
            all(
                z[w["event"]] + 1e-6 * (1 + abs(w["witness_loss_MWh"])) >= w["witness_loss_MWh"] for
                w in m["witnesses"]
            )
        normalcost = q["cost"]
        loss = sum(z)
        isloss = kind == "minimum_selected_worst_loss"
        expectedkind =
            isloss ? "minimum_selected_event_worst_loss_MWh" :
            "normal_cost_plus_worst_loss_penalty_CNY"
        r["objective_kind"] == expectedkind || error("诊断目标类型改变")
        obj = isloss ? loss : normalcost + s["penalty_MWh"] * loss
        objpass = abs(obj - r["solver_objective"]) <= 1e-6 * max(1, abs(obj))
        on = sum(call(:r7_unpack, m["normal"]["chp_values"]["CHP1"], "u_CHP")[win])
        pinpass =
            isloss || (
                r["pinned_event_steps"] == collect(win) && all(
                    abs(t - 1) <= 1e-6 for
                    t in call(:r7_unpack, m["normal"]["chp_values"]["CHP1"], "u_CHP")[win]
                )
            )
        ep == r["epigraph_pass"] && objpass == r["objective_pass"] && pinpass == r["pin_pass"] ||
            error("诊断检查标志不同")
        abs(obj-r["objective_replay"]) <= 1e-6 * max(1, abs(obj)) &&
        abs(normalcost-r["normal_cost_CNY"]) <= 1e-6 * max(1, abs(normalcost)) &&
        abs(loss-r["selected_worst_loss_MWh"]) <= 1e-6 * max(1, abs(loss)) || error("诊断账本不同")
        lower = get(r, "objective_lower_bound", NaN)
        gap = (obj-lower)/max(1, abs(obj))
        passed = q["normal_pass"] && q["included_pass"] && ep && objpass && pinpass
        push!(
            rows,
            row(
                kind,
                r["status"];
                model_pass = passed,
                normal_cost = normalcost,
                loss,
                objective = r["solver_objective"],
                bound = lower,
                units = isloss ? "MWh" : "CNY",
                on_steps = on,
                bound_pass = passed && isfinite(lower) && -1e-6 <= gap <= 1e-4,
                scope = isloss ? "selected 3-fault adopted-model loss bound; cost not optimized" :
                        "pinned-commitment adopted-model penalty objective; independent recovery not performed",
            ),
        )
    end
    Objects.csvbytes(rows)
end

function freeze(input, commitment, floor, out)
    ispath(out) && error("不覆盖诊断证据")
    bytes = make_table(input, commitment, floor)
    stage = out * ".writing"
    ispath(stage) && error("未完成诊断封存已存在")
    mkpath(joinpath(stage, "objects"))
    index = Dict(
        "schema"=>"r9-preplan-diagnostic-evidence-v1",
        "utc"=>string(now(UTC)),
        "input"=>Objects.pack(stage, input),
        "commitment"=>Objects.pack(stage, commitment),
        "floor"=>Objects.pack(stage, floor),
        "optimization_performed"=>false,
        "full_fault_certificate"=>false,
    )
    Evidence.toml(joinpath(stage, "index.toml"), index)
    write(joinpath(stage, "diagnostics.csv"), bytes)
    cp(@__FILE__, joinpath(stage, "report-source.jl"))
    for f in ("r9_preplan_evidence.jl", "r9_resilience_evidence.jl", "r9_fixed_evidence.jl")
        cp(joinpath(@__DIR__, f), joinpath(stage, f))
    end
    Evidence.toml(joinpath(stage, "artifacts.toml"), Dict("files"=>Evidence.files(stage)))
    mv(stage, out)
    println("Preplan diagnostics frozen: ", relpath(out, ROOT))
end

function check(out; replay = false)
    a = TOML.parsefile(joinpath(out, "artifacts.toml"))["files"]
    actual=Evidence.files(out)
    delete!(actual, "artifacts.toml")
    actual==a || error("诊断封存字节改变")
    x=TOML.parsefile(joinpath(out, "index.toml"))
    x["schema"]=="r9-preplan-diagnostic-evidence-v1" &&
    !x["optimization_performed"] &&
    !x["full_fault_certificate"] || error("诊断封存范围不符")
    if replay
        temp=mktempdir(joinpath(ROOT, "tmp"); prefix = "r9-preplan-diagnostics-", cleanup = false)
        for k in ("input", "commitment", "floor")
            Old.extract(out, x[k], joinpath(temp, k))
        end
        m=Module(gensym(:FrozenPreplanDiagnostics))
        Base.include(m, joinpath(out, "report-source.jl"))
        lib=Base.invokelatest(getfield, m, :R9PreplanDiagnosticEvidence)
        fn=Base.invokelatest(getfield, lib, :make_table)
        bytes=Base.invokelatest(
            fn,
            (joinpath(temp, k) for k in ("input", "commitment", "floor"))...,
        )
        bytes==read(joinpath(out, "diagnostics.csv")) || error("诊断表重算不同")
        println("Frozen diagnostics independently replayed: ", relpath(temp, ROOT))
    end
    println("Diagnostic evidence hashes passed: ", length(a))
    true
end
end
if abspath(PROGRAM_FILE)==@__FILE__
    if length(ARGS)==5 && ARGS[1]=="freeze"
        R9PreplanDiagnosticEvidence.freeze(abspath.(ARGS[2:5])...)
    elseif length(ARGS) in (2, 3) && ARGS[1]=="check" && (length(ARGS)==2 || ARGS[3]=="--replay")
        R9PreplanDiagnosticEvidence.check(abspath(ARGS[2]); replay = length(ARGS)==3)
    else
        error(
            "usage: r9_preplan_diagnostic_evidence.jl freeze INPUT COMMITMENT_AUDIT LOSS_AUDIT NEW_EVIDENCE | check EVIDENCE [--replay]",
        )
    end
end
