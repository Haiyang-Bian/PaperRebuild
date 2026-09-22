using PaperRebuild, JuMP, HiGHS, Clarabel, TOML, SHA, Dates
const THERM_ROOT=normpath(joinpath(@__DIR__, ".."))

function thermal_read_frozen(path)
    wrapper=Module(gensym(:ThermalEvidence))
    Base.include(wrapper, abspath(joinpath(path, "code/replay.jl")))
    Base.invokelatest(getfield, wrapper, :x)
end

function thermal_front(s, hot)
    y=deepcopy(s)
    p=only(filter(p->p["side"]=="S", y["profiles"]))
    p["segments"]=[
        Dict(
            "mass_kg"=>5000.0,
            "base_K"=>temp,
            "amplitude_K"=>0.0,
            "rate_per_kg"=>0.0,
            "from_left"=>true,
        ) for temp in (hot ? [333.15, 353.15] : [353.15, 333.15])
    ]
    y["uniform_assumption"]=false
    y["profile_origin"]="frozen analytic spatial front with equal inventory"
    y
end

function thermal_records(dir)
    opt=optimizer_with_attributes(HiGHS.Optimizer, "threads"=>1)
    base=Any[]
    for name in ("thermal-steady", "thermal-front", "recovery-hand")
        c=load_r7_recovery_case(joinpath(THERM_ROOT, "configs/r7/$name.toml"))
        r=solve_r7_recovery(c, name=="recovery-hand" ? [1] : [0]; optimizer = opt, budget_sec = 60)
        r["validation"]["model_pass"] || error("冻结解析父案例无合格恢复候选")
        s=r7_thermal_spec(
            c,
            r;
            profiles = :uniform,
            profile_origin = "explicit uniform assumption, not inferred original spatial history",
        )
        if name=="thermal-front"
            push!(base, (id = "hot_outlet", case = c, parent = r, spec = thermal_front(s, true)))
            push!(base, (id = "cold_outlet", case = c, parent = r, spec = thermal_front(s, false)))
        else
            push!(base, (id = name, case = c, parent = r, spec = s))
        end
    end
    old=joinpath(THERM_ROOT, "results/summaries/r7-nested-reserve-20260920-v1")
    archive=thermal_read_frozen(old)
    archive.validation["robust_model_pass"] || error("原嵌套规划未通过")
    iteration=archive.validation["candidate_iteration"]
    master=archive.result["iterations"][iteration]["master"]
    normal=R7NormalCase(archive.case.normal.data)
    for (i, w) in enumerate(master["witnesses"])
        event_spec=archive.case.specification["events"][w["event"]]
        e=r7_normal_event(
            normal,
            master["normal"];
            event_start = event_spec["event_start"],
            periods = event_spec["periods"],
            renewable_factor = event_spec["renewable_factor"],
            loss_limit_MWh = event_spec["loss_limit_MWh"],
        )
        c=e.case
        # 原安全规划见证只有可行值，没有恢复最优界；重构保持这个证据边界。
        r=Dict{String,Any}(
            "schema"=>"r7-recovery-result-v1",
            "version"=>"r7_recovery_checked_v1",
            "run_id"=>archive.result["run_id"]*"_witness_$i",
            "case_sha256"=>c.sha256,
            "preplan_id"=>c.data["preplan_id"],
            "preplan_optimality_verified"=>false,
            "objective_kind"=>"expected_unserved_energy_MWh",
            "fault"=>w["fault"],
            "status"=>"feasibility_witness",
            "values"=>w["values"],
            "solver_objective_MWh"=>w["witness_loss_MWh"],
        )
        s=r7_thermal_spec(
            c,
            r;
            profiles = e.evidence["initial_pipe_profiles"],
            profile_origin = "frozen nested reserve plan, exact inherited segment profiles",
        )
        s["normal_event_evidence"]=e.evidence
        s["normal_archive_result_sha256"]=bytes2hex(sha256(read(joinpath(old, "result.toml"))))
        push!(base, (id = "nested_witness_$i", case = c, parent = r, spec = s))
    end
    records=Dict{String,Any}[]
    for item in base, n in (1, 4, 16), mode in ("same_dispatch", "curtail_heat")
        s=deepcopy(item.spec)
        s["substeps"]=n
        s["mode"]=mode
        id=item.id*"_n$(n)_"*mode
        push!(
            records,
            Dict(
                "id"=>id,
                "group"=>item.id,
                "case"=>item.case.data,
                "parent"=>item.parent,
                "spec"=>s,
                "solver"=>"HiGHS",
            ),
        )
    end
    for item in base[1:3]
        s=deepcopy(item.spec)
        s["substeps"]=16
        s["mode"]="curtail_heat"
        push!(
            records,
            Dict(
                "id"=>item.id*"_clarabel",
                "group"=>item.id,
                "case"=>item.case.data,
                "parent"=>item.parent,
                "spec"=>s,
                "solver"=>"Clarabel",
            ),
        )
    end
    # 正式热LP优化前冻结所有父值、空间状态、细分和求解器，不能按结果选样。
    write(joinpath(dir, "inputs.toml"), PaperRebuild.r7_text(Dict("records"=>records)))
    records
end

function thermal_tables(dir)
    records=TOML.parsefile(joinpath(dir, "inputs.toml"))["records"]
    summary=IOBuffer()
    trajectory=IOBuffer()
    println(
        summary,
        "record,group,run_id,solver,substeps,mode,status,thermal_pass,same_dispatch,heat_unserved_MWh,lower_bound_MWh,conditional_optimality,port_conflicts,elapsed_sec",
    )
    println(
        trajectory,
        "record,run_id,side,pipe,scenario,time_h,energy_MWh,outlet_mean_K,flow_kg_s",
    )
    for record in records
        x=thermal_read_frozen(joinpath(dir, record["id"]))
        r=x.result
        q=x.validation
        s=x.spec
        PaperRebuild.r7_digest(record["case"])==x.case.sha256 &&
        isequal(record["parent"], x.parent)&&isequal(record["spec"], s) ||
            error("冻结输入与原值不符")
        println(
            summary,
            join(
                [
                    record["id"],
                    record["group"],
                    r["run_id"],
                    record["solver"],
                    s["substeps"],
                    s["mode"],
                    r["status"],
                    q["thermal_model_pass"],
                    q["same_dispatch_pass"],
                    get(q, "heat_unserved_MWh", ""),
                    get(r, "lower_bound_MWh", ""),
                    q["conditional_heat_optimality_pass"],
                    length(q["port_witness"]),
                    r["elapsed_sec"],
                ],
                ',',
            ),
        )
        if haskey(r, "values")
            dt=x.case.data["dt_h"]/s["substeps"]
            T=x.case.data["periods"]*s["substeps"]
            flow=PaperRebuild.r7_unpack(x.parent["values"], "m_pipe")
            for side in ("S", "R")
                E=PaperRebuild.r7_unpack(r["values"], "E_$side")
                O=PaperRebuild.r7_unpack(r["values"], "out_$side")
                for a in axes(E, 1), w in axes(E, 3), k in 0:T
                    f=k==0 ? "" : flow[a, cld(k, s["substeps"])]
                    o=k==0 || f==0 ? "" : O[a, k, w]
                    println(
                        trajectory,
                        join(
                            [record["id"], r["run_id"], side, a, w, k*dt, E[a, k+1, w], o, f],
                            ',',
                        ),
                    )
                end
            end
        end
    end
    Dict("summary.csv"=>String(take!(summary)), "trajectory.csv"=>String(take!(trajectory)))
end

function thermal_run(dir)
    ispath(dir)&&error("不覆盖热研究目录")
    mkpath(dir)
    freeze=TOML.parsefile(joinpath(THERM_ROOT, "configs/r7/thermal-freeze.toml"))
    for (name, entry) in freeze["cases"]
        bytes2hex(sha256(read(joinpath(THERM_ROOT, "configs/r7/$name.toml"))))==entry["file_sha256"] ||
            error("冻结输入改变")
    end
    write(joinpath(dir, "rule.toml"), PaperRebuild.r7_text(freeze))
    records=thermal_records(dir)
    for record in records
        c=R7RecoveryCase(record["case"])
        opt=record["solver"]=="HiGHS" ? optimizer_with_attributes(HiGHS.Optimizer, "threads"=>1) :
            Clarabel.Optimizer
        r=solve_r7_thermal_reconstruction(
            c,
            record["parent"],
            record["spec"];
            optimizer = opt,
            budget_sec = 600,
        )
        save_r7_thermal_reconstruction(
            c,
            record["parent"],
            record["spec"],
            r,
            joinpath(dir, record["id"]),
        )
        println(record["id"], " ", r["status"], " thermal=", r["validation"]["thermal_model_pass"])
        flush(stdout)
    end
    for (p, text) in thermal_tables(dir)
        write(joinpath(dir, p), text)
    end
    cp(@__FILE__, joinpath(dir, "study-source.jl"))
    hashes=Dict(
        replace(relpath(joinpath(p, f), dir), '\\'=>'/')=>bytes2hex(sha256(read(joinpath(p, f))))
        for (p, _, fs) in walkdir(dir) for f in fs
    )
    write(joinpath(dir, "files.toml"), PaperRebuild.r7_text(Dict("files"=>hashes)))
end

function thermal_check(dir)
    files=TOML.parsefile(joinpath(dir, "files.toml"))["files"]
    actual=Set(
        replace(relpath(joinpath(p, f), dir), '\\'=>'/') for (p, _, fs) in walkdir(dir) for f in fs
    )
    actual==union(Set(keys(files)), Set(["files.toml"])) || error("热研究清单不完整")
    for (p, h) in files
        !isabspath(p)&&!occursin(':', p)&&all(s->!(s in ("", ".", "..")), split(p, '/')) ||
            error("路径错误")
        bytes2hex(sha256(read(joinpath(dir, split(p, '/')...))))==h || error("热研究文件篡改")
    end
    for (p, text) in thermal_tables(dir)
        read(joinpath(dir, p), String)==text || error("汇总失配")
    end
    println("Frozen thermal evidence and all original values replayed; no optimization.")
end

if abspath(PROGRAM_FILE)==@__FILE__
    length(ARGS)==2 || error("usage: r7_thermal_study.jl run|check NEW_OR_SAVED_DIRECTORY")
    ARGS[1]=="run" ? thermal_run(abspath(ARGS[2])) :
    ARGS[1]=="check" ? thermal_check(abspath(ARGS[2])) : error("unknown action")
end
