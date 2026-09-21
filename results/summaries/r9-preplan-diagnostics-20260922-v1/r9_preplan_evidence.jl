# 封存并独立重读灾前共同决策及六项恢复；只读原值，不求解或修改原运行。
module R9PreplanEvidence
using TOML, SHA, CSV, Dates
include("r9_resilience_evidence.jl")
const Old=R9ResilienceEvidence
const Objects=Old.Objects
const ROOT=dirname(@__DIR__)
hashfile(p) = bytes2hex(sha256(read(p)))
toml(p, x) = open(io->TOML.print(io, x; sorted = true), p, "w")
function files(folder)
    Dict(
        replace(relpath(joinpath(d, f), folder), '\\'=>'/')=>hashfile(joinpath(d, f)) for
        (d, _, fs) in walkdir(folder) for f in fs
    )
end
function verify_input(input)
    m=TOML.parsefile(joinpath(input, "files.toml"))
    m["schema"]=="r9-preplan-input-v1" || error("灾前冻结版本不同")
    actual=files(input)
    delete!(actual, "files.toml")
    actual==m["files"] || error("冻结输入不符")
    for p in keys(actual)
        Old.safe(input, p)
    end
    parent=TOML.parsefile(joinpath(input, "parent-files.toml"))
    p=TOML.parsefile(joinpath(input, "protocol.toml"))
    hashfile(joinpath(input, "parent-files.toml"))==p["parent_manifest_sha256"]==m["parent_manifest_sha256"] ||
        error("父输入清单不符")
    for f in ("normal.toml", "planning.toml", "construction.toml")
        hashfile(joinpath(input, f))==parent["files"][p["critical_set"]*"/"*f] ||
            error("原物理输入被改变")
    end
    p
end
function verify_method(dir, input, mode)
    d=TOML.parsefile(joinpath(dir, "files.toml"))["files"]
    actual=files(dir)
    delete!(actual, "files.toml")
    delete!(actual, "execution.toml")
    actual==d || error("完整方法文件被改变")
    e=TOML.parsefile(joinpath(dir, "execution.toml"))
    p=TOML.parsefile(joinpath(input, "protocol.toml"))
    e["schema"]=="r9-preplan-execution-v1" &&
    e["mode"]==mode &&
    e["input_manifest_sha256"]==hashfile(joinpath(input, "files.toml")) &&
    e["budget_sec"]==p["budget_sec"] &&
    e["budget_pass"]==(e["total_wall_sec"]<=e["budget_sec"]) &&
    e["whole_fault_universe_certified"]===false &&
    e["free_flow_preplan_certified"]===false || error("完整方法身份或预算判定错误")
    inputfiles=TOML.parsefile(joinpath(input, "files.toml"))["files"]
    inputmanifest=TOML.parsefile(joinpath(input, "files.toml"))
    Set(keys(e["source_hashes"]))==Set(inputmanifest["code"]) &&
    all(get(inputfiles, "code/"*k, "")==h for (k, h) in e["source_hashes"]) ||
        error("执行源码与输入冻结不同")
    expected=[kind*"-"*id for id in p["fault_ids"] for kind in ("aggregate", "detailed")]
    [s["stage"] for s in e["stages"]]==expected || error("恢复阶段缺失、重复或重排")
    e
end
function method_tables(input, dir, mode)
    exec=verify_method(dir, input, mode)
    replay=Old.frozen_read(joinpath(dir, "primary"))
    x=replay.data
    c, s, r, q=x.case, x.spec, x.result, x.validation
    c.normal.data==TOML.parsefile(joinpath(input, "normal.toml")) &&
    c.specification==TOML.parsefile(joinpath(input, "planning.toml")) &&
    s==TOML.parsefile(joinpath(input, mode*"-spec.toml")) &&
    r["run_id"]==exec["primary_run_id"] &&
    r["status"]==exec["primary_status"] || error("主阶段不是冻结输入")
    p=TOML.parsefile(joinpath(input, "protocol.toml"))
    records=NamedTuple[]
    commitments=NamedTuple[]
    witnesses=NamedTuple[]
    states=NamedTuple[]
    if haskey(r, "master") && get(q, "normal_model_pass", false)
        n=r["master"]["normal"]
        normal=(; case = c.normal, result = n, validation = q["master_check"]["normal_check"])
        push!(records, (stage = "normal", replay = (data = normal,), execution = exec))
        for g in c.normal.data["devices"]
            g["kind"]=="CHP" || continue
            v=n["chp_values"][g["id"]]
            u=Old.unpack(v, "u_CHP")
            for t in eachindex(u)
                push!(
                    commitments,
                    (
                        mode = mode,
                        run_id = n["run_id"],
                        device = g["id"],
                        time_h = (t-1)*c.normal.data["dt_h"],
                        commitment = u[t],
                    ),
                )
            end
        end
        for w in q["master_check"]["witness_checks"]
            v=w["check"]
            push!(
                witnesses,
                (
                    mode = mode,
                    run_id = r["run_id"],
                    pair = w["key"],
                    model_pass = v["model_pass"],
                    loss_MWh = get(v, "loss_MWh", NaN),
                    exchange_exact_pass = get(v, "exchange_exact_pass", false),
                    original_limit_MWh = p["loss_limit_MWh"],
                    carrier_limit_pass = w["threshold_pass"],
                ),
            )
        end
    end
    if any(z["attempted"] for z in exec["stages"])
        r["candidate_accepted"] || error("不合格正常结果不能生成恢复")
        lib=Base.invokelatest(getfield, replay.mod, :FrozenR9Preplan)
        event=Base.invokelatest(
            Base.invokelatest(getfield, lib, :r7_planning_event),
            c,
            r["master"]["normal"],
            1,
        )
        event.case.data==TOML.parsefile(joinpath(dir, "event.toml")) &&
        event.evidence==TOML.parsefile(joinpath(dir, "inheritance.toml")) ||
            error("正常事件继承不同")
        for z in event.evidence["initial_pipe_profiles"]
            push!(
                states,
                (
                    mode = mode,
                    parent_run_id = event.evidence["parent_run_id"],
                    pipe = z["pipe"],
                    side = z["side"],
                    scenario = z["scenario"],
                    mass_kg = z["mass_kg"],
                    mean_K = z["mean_K"],
                    relative_heat_MWh = z["relative_heat_MWh"],
                ),
            )
        end
        construction=TOML.parsefile(joinpath(input, "construction.toml"))
        for stage in exec["stages"]
            label=stage["stage"]
            if !stage["attempted"]
                ispath(joinpath(dir, label)) && error("未执行阶段存在运行目录")
                continue
            end
            loaded=Old.frozen_read(joinpath(dir, label))
            y=loaded.data
            bits=split(label, '-'; limit = 2)
            y.case.data==event.case.data &&
            y.result["fault"]==construction["pilot_faults"][bits[2]] &&
            y.result["run_id"]==stage["run_id"] &&
            y.result["status"]==stage["status"] &&
            y.validation["model_pass"]==stage["model_pass"] &&
            isequal(get(y.validation, "loss_MWh", NaN), stage["loss_MWh"]) ||
                error("恢复阶段身份、原值或范围错误")
            if bits[1]=="detailed"
                y.spec["profiles"]==event.evidence["initial_pipe_profiles"] ||
                    error("详细初态不完整")
                y.spec==TOML.parsefile(joinpath(dir, "transport-spec.toml")) ||
                    error("详细输运规格不同")
                ev=only(c.specification["events"])
                win=ev["event_start"]:(ev["event_start"]+ev["periods"]-1)
                h=c.normal.data["heat"]
                flows=Dict(
                    "m_pipe"=>reduce(
                        vcat,
                        [permutedims(z["normal_flow_kg_s"][win]) for z in h["pipes"]],
                    ),
                    "m_source"=>reduce(vcat, [permutedims(z[win]) for z in h["source_flow_kg_s"]]),
                    "m_load"=>reduce(vcat, [permutedims(z[win]) for z in h["load_flow_kg_s"]]),
                )
                all(Old.unpack(y.spec["flow_schedule"], k)==v for (k, v) in flows) &&
                y.spec["substeps"]==p["recovery_substeps"] &&
                !y.spec["uniform_assumption"] ||
                    error("详细恢复没有保持声明的正常参考流或子步/完整空间状态")
            end
            push!(records, (stage = label, replay = loaded, execution = exec))
        end
    end
    tables=isempty(records) ? Dict{String,Vector{UInt8}}() : Old.make_tables(records)
    primary=(
        mode = mode,
        run_id = r["run_id"],
        status = r["status"],
        model_pass = q["model_pass"],
        normal_cost_CNY = get(q, "normal_cost", NaN),
        penalty_cost_CNY = get(q, "penalty_cost", NaN),
        objective_CNY = get(q, "objective", NaN),
        objective_lower_CNY = get(r, "objective_lower_bound", NaN),
        relative_gap = get(q, "relative_gap", NaN),
        objective_complete = q["objective_optimality_pass"],
        selected_threshold_witness_pass = q["selected_threshold_witness_pass"],
        whole_fault_threshold_witness_pass = q["whole_fault_threshold_witness_pass"],
        selected_pairs = q["selected_fault_pairs"],
        whole_pairs = q["whole_fault_pairs"],
        independent_attempted = count(z->z["attempted"], exec["stages"]),
        independent_model_pass = count(z->get(z, "model_pass", false), exec["stages"]),
        total_wall_sec = exec["total_wall_sec"],
        budget_pass = exec["budget_pass"],
    )
    (; tables, primary, commitments, witnesses, states)
end
function make_tables(input, raw)
    p=verify_input(input)
    collected=Dict{String,Vector{NamedTuple}}()
    primary=NamedTuple[]
    commitments=NamedTuple[]
    witnesses=NamedTuple[]
    states=NamedTuple[]
    for mode in p["modes"]
        println("Replaying preplan method ", mode)
        flush(stdout)
        x=method_tables(input, Old.safe(raw, mode), mode)
        push!(primary, x.primary)
        append!(commitments, x.commitments)
        append!(witnesses, x.witnesses)
        append!(states, x.states)
        for (file, bytes) in x.tables
            rows=get!(collected, file, NamedTuple[])
            for row in CSV.File(IOBuffer(bytes))
                push!(rows, merge((mode = mode,), NamedTuple(row)))
            end
        end
    end
    collected["primary.csv"]=primary
    collected["commitments.csv"]=commitments
    isempty(witnesses) || (collected["witnesses.csv"]=witnesses)
    isempty(states) || (collected["initial-states.csv"]=states)
    Dict(file=>Objects.csvbytes(rows) for (file, rows) in collected)
end
function freeze(input, raw, out)
    ispath(out) && error("不覆盖灾前证据")
    tables=make_tables(input, raw)
    p=verify_input(input)
    stage=out*".writing"
    ispath(stage) && error("未完成封存已存在")
    mkpath(joinpath(stage, "objects"))
    index=Dict(
        "schema"=>"r9-preplan-evidence-v1",
        "utc"=>string(now(UTC)),
        "input"=>Objects.pack(stage, input),
        "methods"=>Dict(mode=>Objects.pack(stage, joinpath(raw, mode)) for mode in p["modes"]),
        "origin"=>p["origin"],
        "whole_fault_universe_certified"=>false,
        "free_flow_preplan_certified"=>false,
        "optimization_performed"=>false,
    )
    toml(joinpath(stage, "index.toml"), index)
    for (f, bytes) in tables
        write(joinpath(stage, f), bytes)
    end
    cp(@__FILE__, joinpath(stage, "report-source.jl"))
    for f in ("r9_resilience_evidence.jl", "r9_fixed_evidence.jl")
        cp(joinpath(@__DIR__, f), joinpath(stage, f))
    end
    toml(joinpath(stage, "artifacts.toml"), Dict("files"=>files(stage)))
    mv(stage, out)
    println("Preplan evidence frozen ", relpath(out, ROOT))
end
function check(out; replay = false)
    expected=TOML.parsefile(joinpath(out, "artifacts.toml"))["files"]
    actual=files(out)
    delete!(actual, "artifacts.toml")
    actual==expected || error("灾前证据字节或文件集合改变")
    index=TOML.parsefile(joinpath(out, "index.toml"))
    index["schema"]=="r9-preplan-evidence-v1" &&
    !index["optimization_performed"] &&
    !index["whole_fault_universe_certified"] &&
    !index["free_flow_preplan_certified"] || error("证据范围错误")
    if replay
        temp=mktempdir(joinpath(ROOT, "tmp"); prefix = "r9-preplan-replay-", cleanup = false)
        input=joinpath(temp, "input")
        Old.extract(out, index["input"], input)
        raw=joinpath(temp, "runs")
        mkpath(raw)
        for (mode, entries) in index["methods"]
            Old.extract(out, entries, Old.safe(raw, mode))
        end
        m=Module(gensym(:FrozenPreplanReport))
        Base.include(m, joinpath(out, "report-source.jl"))
        lib=Base.invokelatest(getfield, m, :R9PreplanEvidence)
        fn=Base.invokelatest(getfield, lib, :make_tables)
        for (file, bytes) in Base.invokelatest(fn, input, raw)
            bytes==read(joinpath(out, file)) || error("图源重算失步：$file")
        end
        println("Frozen preplan values and inheritance replay passed: ", relpath(temp, ROOT))
    end
    println("Preplan evidence hashes passed: ", length(expected))
    true
end
end
if abspath(PROGRAM_FILE)==@__FILE__
    if length(ARGS)==4 && ARGS[1]=="freeze"
        R9PreplanEvidence.freeze(abspath(ARGS[2]), abspath(ARGS[3]), abspath(ARGS[4]))
    elseif length(ARGS) in (2, 3) && ARGS[1]=="check" && (length(ARGS)==2 || ARGS[3]=="--replay")
        R9PreplanEvidence.check(abspath(ARGS[2]); replay = length(ARGS)==3)
    else
        error(
            "usage: r9_preplan_evidence.jl freeze INPUT RAW NEW_EVIDENCE | check EVIDENCE [--replay]",
        )
    end
end
