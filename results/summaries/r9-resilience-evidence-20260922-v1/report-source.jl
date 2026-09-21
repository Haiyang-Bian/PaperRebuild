# 只读原运行、冻结原字节、复算继承和图源；不调用优化器。
module R9ResilienceEvidence
using TOML, SHA, CSV, Dates
include("r9_fixed_evidence.jl")
const Objects=R9FixedEvidence
const ROOT=dirname(@__DIR__)
hashfile(p) = bytes2hex(sha256(read(p)))
toml(p, x) = open(io->TOML.print(io, x; sorted = true), p, "w")

function safe(root, p)
    !isabspath(p) &&
    !occursin(':', p) &&
    !occursin('\\', p) &&
    all(x->!(x in ("", ".", "..")), split(p, '/')) || error("非法相对证据路径")
    joinpath(root, split(p, '/')...)
end
function extract(root, files, out)
    ispath(out) && error("不覆盖解包目录")
    mkpath(out)
    for (p, h) in files
        file=safe(out, p)
        mkpath(dirname(file))
        write(file, Objects.bytes(root, h))
    end
end

# 每个记录使用随记录保存的科学源码；不依赖当前工作树的模型版本。
function frozen_read(dir)
    m=Module(gensym(:ResilienceReplay))
    Base.include(m, joinpath(dir, "code/replay.jl"))
    (; data = Base.invokelatest(getfield, m, :x), mod = m)
end
function verify_input(dir)
    d=TOML.parsefile(joinpath(dir, "files.toml"))
    d["schema"]=="r9-resilience-freeze-v1" || error("输入冻结版本")
    names=Set(
        replace(relpath(joinpath(p, f), dir), '\\'=>'/') for (p, _, fs) in walkdir(dir) for f in fs
    )
    names==union(Set(keys(d["files"])), Set(["files.toml"])) || error("输入文件集合改变")
    for (p, h) in d["files"]
        hashfile(safe(dir, p))==h || error("输入冻结字节改变")
    end
    d
end

"""
    capacity_certificate(event_data)

项目式R9-RW3：仅适用于无电池、单情景、外网全断的本批输入。忽略电锅炉和普通负荷耗电、
网络及爬坡约束，用已继承CHP承诺、GT额定与降额PV计算发电上界和关键失供下界。
单位MW/MWh，历史启停不改；下界合格不能证明某个调度可行，亦不是自由灾前规划的界。
"""
function capacity_certificate(d)
    d["schema"]=="r7-recovery-case-v1" && d["probabilities"]==[1.0] || error("仅支持单情景恢复")
    all(g->g["kind"] in ("CHP", "GT", "PV", "EB"), d["devices"]) ||
        error("容量证书未包含该设备类型")
    d["dt_h"]>0 || error("无效步长")
    rows=NamedTuple[]
    for t in 1:d["periods"]
        demand=sum(x[t] for x in d["load_service"]["critical_load_MW"])
        chp=sum(
            (g["P_max_MW"]*g["commitment"][t] for g in d["devices"] if g["kind"]=="CHP");
            init = 0.0,
        )
        gt=sum((g["P_max_MW"] for g in d["devices"] if g["kind"]=="GT"); init = 0.0)
        pv=sum(
            (
                d["renewable_factor"]*g["available_MW"][t][1] for
                g in d["devices"] if g["kind"]=="PV"
            );
            init = 0.0,
        )
        all(isfinite, (demand, chp, gt, pv)) && min(demand, chp, gt, pv)>=0 || error("证书输入非法")
        push!(
            rows,
            (
                t = t,
                critical_MW = demand,
                chp_cap_MW = chp,
                gt_cap_MW = gt,
                pv_cap_MW = pv,
                generation_upper_MW = chp+gt+pv,
                unserved_lower_MW = max(0, demand-chp-gt-pv),
            ),
        )
    end
    (;
        rows,
        critical_MWh = d["dt_h"]*sum(x.critical_MW for x in rows),
        generation_upper_MWh = d["dt_h"]*sum(x.generation_upper_MW for x in rows),
        unserved_lower_MWh = d["dt_h"]*sum(x.unserved_lower_MW for x in rows),
    )
end

function check_inheritance(input, records, key)
    normal=only(filter(x->x.stage=="normal", records))
    lib=Base.invokelatest(getfield, normal.replay.mod, :FrozenR7Normal)
    parent=normal.replay.data
    parent.case.data==TOML.parsefile(joinpath(input, key, "normal.toml")) ||
        error("正常输入身份错误")
    p=TOML.parsefile(joinpath(input, key, "planning.toml"))
    ev=only(p["events"])
    event=Base.invokelatest(
        Base.invokelatest(getfield, lib, :r7_normal_event),
        parent.case,
        parent.result;
        event_start = ev["event_start"],
        periods = ev["periods"],
        renewable_factor = ev["renewable_factor"],
        loss_limit_MWh = ev["loss_limit_MWh"],
    )
    adopted=Base.invokelatest(
        Base.invokelatest(getfield, lib, :with_r7_port_temperature_bounds),
        event.case,
    )
    construction=TOML.parsefile(joinpath(input, key, "construction.toml"))
    for row in records
        r=row.replay.data
        row.execution["input_manifest_sha256"]==hashfile(joinpath(input, "files.toml")) ||
            error("运行输入清单不符")
        row.execution["run_id"]==r.result["run_id"] || error("阶段运行身份不符")
        row.execution["budget_pass"]==(
            row.execution["total_wall_sec"]<=row.execution["budget_sec"]
        ) || error("预算判定不符")
        row.stage=="normal" && continue
        inheritance=row.inheritance
        inheritance["parent_normal_run_id"]==parent.result["run_id"] || error("继承了别的正常调度")
        inheritance["event_boundary"]==event.evidence || error("事件边界未按原正常状态继承")
        inheritance["parent_normal_result_sha256"]==Base.invokelatest(
            Base.invokelatest(getfield, lib, :r7_digest),
            parent.result,
        ) || error("父数值身份错误")
        adopted.data==r.case.data && adopted.sha256==inheritance["adopted_event_case_sha256"] ||
            error("恢复输入被改写")
        fault=split(row.stage, '-'; limit = 2)[2]
        r.result["fault"]==construction["pilot_faults"][fault] || error("故障与冻结协议不同")
        if startswith(row.stage, "detailed-")
            r.spec["profiles"]==event.evidence["initial_pipe_profiles"] || error("逐管初态未继承")
        end
    end
    true
end
unpack(v, k) = reshape(Float64.(v[k]["data"]), Tuple(Int.(v[k]["shape"])))
function make_tables(records)
    summary, trajectory, residuals, capacity, devices=NamedTuple[],
    NamedTuple[],
    NamedTuple[],
    NamedTuple[],
    NamedTuple[]
    for row in records
        x=row.replay.data
        r=x.result
        v=x.validation
        d=x.case.data
        normal=row.stage=="normal"
        detailed=startswith(row.stage, "detailed-")
        good=get(v, "model_pass", false)
        cert=normal ? nothing : capacity_certificate(d)
        push!(
            summary,
            (
                stage = row.stage,
                run_id = r["run_id"],
                status = r["status"],
                model_pass = good,
                thermal_replay = normal ? string(get(v, "pipe_reference_pass", false)) :
                                 detailed ?
                                 string(
                    get(get(v, "thermal", Dict()), "same_dispatch_pass", false),
                ) : "not_checked",
                normal_cost_CNY = normal ? get(v, "cost", NaN) : NaN,
                critical_MWh = normal ? NaN : cert.critical_MWh,
                critical_unserved_MWh = get(v, "loss_critical_electric_MWh", NaN),
                ordinary_unserved_MWh = get(v, "loss_ordinary_electric_MWh", NaN),
                heat_unserved_MWh = get(v, "loss_heat_MWh", NaN),
                analytic_lower_MWh = normal ? NaN : cert.unserved_lower_MWh,
                solver_lower_MWh = get(r, "lower_bound_MWh", NaN),
                relative_gap = get(v, "relative_gap", NaN),
                conditional_optimality = get(
                    v,
                    detailed ? "conditional_optimality_pass" : "optimality_pass",
                    false,
                ),
                wall_sec = row.execution["total_wall_sec"],
                budget_pass = row.execution["budget_pass"],
                critical_limit_pass = normal ? false :
                                      good &&
                                      v["loss_critical_electric_MWh"]<=d["loss_limit_MWh"]+1e-6*d["dt_h"],
            ),
        )
        if !normal
            for z in cert.rows
                push!(
                    capacity,
                    merge(
                        (stage = row.stage, run_id = r["run_id"], time_h = 10+(z.t-1)*d["dt_h"]),
                        z,
                    ),
                )
            end
        end
        blocks=detailed ?
               ["shared"=>get(v, "shared", Dict()), "thermal"=>get(v, "thermal", Dict())] :
               ["model"=>v]
        for (name, b) in blocks
            rows=get(b, "rows", Dict[])
            for id in sort(unique(String(z["id"]) for z in rows))
                selection=filter(z->z["id"]==id, rows)
                ratios=[z["residual"]/z["tolerance"] for z in selection]
                i=argmax(ratios)
                w=selection[i]
                push!(
                    residuals,
                    (
                        stage = row.stage,
                        run_id = r["run_id"],
                        block = name,
                        formula = id,
                        rows = length(selection),
                        maximum_normalized = ratios[i],
                        raw_residual = w["residual"],
                        tolerance = w["tolerance"],
                        unit = w["unit"],
                        all_pass = all(z->z["pass"], selection),
                    ),
                )
            end
        end
        haskey(r, "values") || continue
        vals=r["values"]
        P=unpack(vals, "P")
        H=unpack(vals, "H")
        pcc=unpack(vals, "P_PCC")
        for t in 1:d["periods"]
            time_h=(normal ? 0 : 10)+(t-1)*d["dt_h"]
            gen=sum(
                P[g, t, 1] for
                (g, dev) in enumerate(d["devices"]) if dev["kind"] in ("CHP", "GT", "PV")
            )
            critical=normal ? NaN : cert.rows[t].critical_MW
            shed=normal ? NaN : sum(unpack(vals, "P_shed_critical")[:, t, 1])
            heat_shed=normal ? NaN : sum(unpack(vals, "H_shed")[:, t, 1])
            push!(
                trajectory,
                (
                    stage = row.stage,
                    run_id = r["run_id"],
                    time_h = time_h,
                    generation_MW = gen,
                    pcc_MW = pcc[t, 1],
                    critical_MW = critical,
                    critical_served_MW = critical-shed,
                    critical_unserved_MW = shed,
                    heat_unserved_MW = heat_shed,
                ),
            )
            for (g, dev) in enumerate(d["devices"])
                push!(
                    devices,
                    (
                        stage = row.stage,
                        run_id = r["run_id"],
                        time_h = time_h,
                        device = dev["id"],
                        kind = dev["kind"],
                        P_MW = P[g, t, 1],
                        H_MW = H[g, t, 1],
                    ),
                )
            end
        end
    end
    Dict(
        "summary.csv"=>Objects.csvbytes(summary),
        "trajectories.csv"=>Objects.csvbytes(trajectory),
        "residuals.csv"=>Objects.csvbytes(residuals),
        "capacity.csv"=>Objects.csvbytes(capacity),
        "devices.csv"=>Objects.csvbytes(devices),
    )
end

function freeze(input, raw, key, out)
    ispath(out) && error("不覆盖原证据")
    verify_input(input)
    p=TOML.parsefile(joinpath(input, "protocol.toml"))
    key in p["critical_sets"] || error("未声明分类")
    stages=vcat(
        ["normal"],
        [m*"-"*f for m in ("aggregate", "detailed") for f in p["pilot"]["fault_ids"]],
    )
    records=NamedTuple[]
    for stage in stages
        dir=joinpath(raw, key, stage)
        replay=frozen_read(dir)
        execution=TOML.parsefile(dir*"-execution.toml")
        inheritance=stage=="normal" ? Dict() : TOML.parsefile(dir*"-inheritance.toml")
        push!(records, (; stage, replay, execution, inheritance))
    end
    check_inheritance(input, records, key)
    tables=make_tables(records)
    temp=out*".writing"
    ispath(temp) && error("已有未完成封存")
    mkpath(joinpath(temp, "objects"))
    entries=Dict{String,Any}[]
    for r in records
        dir=joinpath(raw, key, r.stage)
        entry=Dict{String,Any}(
            "stage"=>r.stage,
            "files"=>Objects.pack(temp, dir),
            "execution"=>Objects.object(temp, read(dir*"-execution.toml")),
        )
        r.stage=="normal" ||
            (entry["inheritance"]=Objects.object(temp, read(dir*"-inheritance.toml")))
        push!(entries, entry)
    end
    index=Dict(
        "schema"=>"r9-resilience-evidence-v1",
        "created_utc"=>string(now(UTC)),
        "critical_set"=>key,
        "input"=>Objects.pack(temp, input),
        "records"=>entries,
        "origin"=>p["origin"],
        "whole_fault_universe_certified"=>false,
        "free_flow_preplan_certified"=>false,
        "report_script_sha256"=>hashfile(@__FILE__),
    )
    toml(joinpath(temp, "index.toml"), index)
    for (name, bytes) in tables
        write(joinpath(temp, name), bytes)
    end
    cp(@__FILE__, joinpath(temp, "report-source.jl"))
    cp(joinpath(@__DIR__, "r9_fixed_evidence.jl"), joinpath(temp, "r9_fixed_evidence.jl"))
    hashes=Dict(
        replace(relpath(joinpath(p, f), temp), '\\'=>'/')=>hashfile(joinpath(p, f)) for
        (p, _, fs) in walkdir(temp) for f in fs
    )
    toml(joinpath(temp, "artifacts.toml"), Dict("files"=>hashes, "optimization_performed"=>false))
    mv(temp, out)
    println("Evidence frozen: ", relpath(out, ROOT), "; runs=", length(records))
end

function check(out; replay = false)
    a=TOML.parsefile(joinpath(out, "artifacts.toml"))
    !a["optimization_performed"] || error("报告不应优化")
    actual=Set(
        replace(relpath(joinpath(p, f), out), '\\'=>'/') for (p, _, fs) in walkdir(out) for f in fs
    )
    actual==union(Set(keys(a["files"])), Set(["artifacts.toml"])) || error("证据文件集合变化")
    for (p, h) in a["files"]
        hashfile(safe(out, p))==h || error("证据字节变化：$p")
    end
    index=TOML.parsefile(joinpath(out, "index.toml"))
    index["schema"]=="r9-resilience-evidence-v1" || error("证据版本")
    if replay
        temp=mktempdir(joinpath(ROOT, "tmp"); prefix = "r9-resilience-replay-", cleanup = false)
        input=joinpath(temp, "input")
        extract(out, index["input"], input)
        verify_input(input)
        records=NamedTuple[]
        for entry in index["records"]
            stage=entry["stage"]
            dir=safe(temp, stage)
            extract(out, entry["files"], dir)
            x=frozen_read(dir)
            execution=Objects.parseobject(out, entry["execution"])
            inheritance=haskey(entry, "inheritance") ?
                        Objects.parseobject(out, entry["inheritance"]) : Dict()
            push!(records, (; stage, replay = x, execution, inheritance))
        end
        check_inheritance(input, records, index["critical_set"])
        for (file, bytes) in make_tables(records)
            bytes==read(joinpath(out, file)) || error("原值重算图源不一致：$file")
        end
        println("Frozen numeric replay and event inheritance passed: ", relpath(temp, ROOT))
    end
    println("Resilience evidence hashes passed: ", length(a["files"]))
    true
end
end

if abspath(PROGRAM_FILE)==@__FILE__
    if length(ARGS)==5 && ARGS[1]=="freeze"
        R9ResilienceEvidence.freeze(abspath(ARGS[2]), abspath(ARGS[3]), ARGS[4], abspath(ARGS[5]))
    elseif length(ARGS) in (2, 3) && ARGS[1]=="check" && (length(ARGS)==2 || ARGS[3]=="--replay")
        R9ResilienceEvidence.check(abspath(ARGS[2]); replay = length(ARGS)==3)
    else
        error("usage: freeze INPUT RAW KEY NEW_EVIDENCE | check EVIDENCE [--replay]")
    end
end
