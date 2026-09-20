using PaperRebuild, JuMP, TOML, SHA
const TRANSPORT_ROOT=normpath(joinpath(@__DIR__, ".."))
const TRANSPORT_MODULES=Dict{String,Module}()
if length(ARGS)==3 && ARGS[1]=="run"
    if ARGS[3]=="open"
        using HiGHS, Clarabel
    elseif ARGS[3]=="gurobi"
        using Gurobi
    end
end
transport_manifest(dir) = Dict(
    replace(relpath(joinpath(p, f), dir), '\\'=>'/')=>bytes2hex(sha256(read(joinpath(p, f))))
    for (p, _, fs) in walkdir(dir) for f in fs if joinpath(p, f)!=joinpath(dir, "files.toml")
)

function transport_read(path)
    key=PaperRebuild.r7_digest(
        TOML.parsefile(joinpath(path, "result.toml"))["source_hashes_at_solve"],
    )
    if !haskey(TRANSPORT_MODULES, key)
        wrapper=Module(gensym(:TransportEvidence))
        Base.include(wrapper, abspath(joinpath(path, "code/replay.jl")))
        TRANSPORT_MODULES[key]=Base.invokelatest(getfield, wrapper, :FrozenR7Transport)
        return Base.invokelatest(getfield, wrapper, :x)
    end
    mod=TRANSPORT_MODULES[key]
    Base.invokelatest(Base.invokelatest(getfield, mod, :read_r7_transport_recovery), path)
end

function transport_freeze(dest)
    ispath(dest)&&error("不覆盖输运冻结目录")
    rule=TOML.parsefile(joinpath(TRANSPORT_ROOT, "configs/r7/transport-study.toml"))
    sources=Dict{String,Any}[]
    records=Dict{String,Any}[]
    function add(c, s, group, label, fault, solver, kind)
        push!(
            records,
            Dict(
                "id"=>"$(group)_$(label)_fault$(only(fault))_$(lowercase(solver))_n$(s["substeps"])",
                "group"=>group,
                "flow_label"=>label,
                "fault"=>fault,
                "solver"=>solver,
                "kind"=>kind,
                "case"=>c.data,
                "case_sha256"=>c.sha256,
                "spec"=>s,
                "spec_sha256"=>PaperRebuild.r7_digest(s),
            ),
        )
    end
    for group in rule["groups"]
        path=joinpath(
            TRANSPORT_ROOT,
            "results/summaries/r7-ports-20260920-v1/thermal",
            group*"_fault0_highs",
        )
        manifest=TOML.parsefile(joinpath(path, "files.toml"))["files"]
        for p in ("case.toml", "spec.toml", "parent.toml")
            bytes2hex(sha256(read(joinpath(path, p))))==manifest[p] || error("原父输入改变")
        end
        c=load_r7_recovery_case(joinpath(path, "case.toml"))
        parent=TOML.parsefile(joinpath(path, "parent.toml"))
        ts=TOML.parsefile(joinpath(path, "spec.toml"))
        validate_r7_recovery(c, parent)["model_pass"] || error("原父代理调度未通过")
        witness=r7_transport_port_witness(c, parent, ts)
        push!(
            sources,
            Dict(
                "group"=>group,
                "path"=>replace(relpath(path, TRANSPORT_ROOT), '\\'=>'/'),
                "manifest_sha256"=>bytes2hex(sha256(read(joinpath(path, "files.toml")))),
                "case"=>c.data,
                "parent"=>parent,
                "thermal_spec"=>ts,
                "witness"=>witness,
            ),
        )
        h=c.data["heat"]
        T=c.data["periods"]
        length(h["pipes"])==1 || error("本冻结协议仅声明单源双节点输入")
        a=only(h["pipes"])
        i=a["from"]
        j=a["to"]
        f=maximum(sum(h["load_MW"][n][t] for n in 1:h["nodes"]) for t in 1:T)/(
            h["c_J_kgK"]/1e6*(h["S_reference_K"]-h["R_reference_K"])
        )
        ref=Dict(
            "m_pipe"=>fill(f, 1, T),
            "m_source"=>zeros(h["nodes"], T),
            "m_load"=>zeros(h["nodes"], T),
        )
        ref["m_source"][i, :].=f
        ref["m_load"][j, :].=f
        flows=Dict(
            "parent"=>Dict(k=>PaperRebuild.r7_unpack(parent["values"], k) for k in keys(ref)),
            "reference"=>ref,
            "zero"=>Dict(k=>zeros(size(v)) for (k, v) in ref),
        )
        function spec(label, n)
            r7_transport_spec(
                c;
                flow_schedule = flows[label],
                profiles = ts["profiles"],
                profile_origin = ts["profile_origin"],
                uniform_assumption = ts["uniform_assumption"],
                substeps = n,
            )
        end
        for label in rule["main_flows"], fault in rule["faults"], solver in rule["main_solvers"]
            add(c, spec(label, rule["substeps"]), group, label, fault, solver, "main")
        end
        for fault in rule["faults"]
            add(c, spec("zero", rule["substeps"]), group, "zero", fault, "HiGHS", "zero")
        end
        add(
            c,
            spec("reference", rule["substeps"]),
            group,
            "reference",
            [0],
            "Clarabel",
            "open_reference",
        )
        if group=="hand"
            for label in rule["main_flows"], n in rule["refinement_substeps"]
                add(c, spec(label, n), group, label, [0], "HiGHS", "refinement")
            end
        end
    end
    length(records)==rule["record_count"] || error("冻结数量错误")
    mkpath(dest)
    write(
        joinpath(dest, "inputs.toml"),
        PaperRebuild.r7_text(Dict("sources"=>sources, "records"=>records)),
    )
    write(joinpath(dest, "rule.toml"), PaperRebuild.r7_text(rule))
    cp(@__FILE__, joinpath(dest, "study-source.jl"))
    for (p, f) in PaperRebuild.r7_transport_science_paths()
        target=joinpath(dest, "code", split(p, '/')...)
        mkpath(dirname(target))
        cp(f, target)
    end
    write(
        joinpath(dest, "freeze.toml"),
        PaperRebuild.r7_text(
            Dict(
                "files"=>transport_manifest(dest),
                "science"=>PaperRebuild.r7_transport_science_hashes(),
            ),
        ),
    )
    println(
        "37 original-state redispatch inputs and transport witnesses frozen before formal optimization.",
    )
end

function transport_inputs(dir; current = false)
    d=TOML.parsefile(joinpath(dir, "freeze.toml"))
    for (p, h) in d["files"]
        !isabspath(p)&&!occursin(':', p)&&all(x->!(x in ("", ".", "..")), split(p, '/')) ||
            error("冻结路径非法")
        bytes2hex(sha256(read(joinpath(dir, split(p, '/')...))))==h || error("冻结文件改变")
    end
    if current
        PaperRebuild.r7_transport_science_hashes()==d["science"] || error("科学源码与冻结不符")
        read(@__FILE__)==read(joinpath(dir, "study-source.jl")) || error("编排脚本与冻结不符")
    end
    TOML.parsefile(joinpath(dir, "inputs.toml")), TOML.parsefile(joinpath(dir, "rule.toml"))
end

function transport_optimizer(name)
    name=="HiGHS" && return optimizer_with_attributes(
        HiGHS.Optimizer,
        "threads"=>1,
        "primal_feasibility_tolerance"=>1e-9,
        "dual_feasibility_tolerance"=>1e-9,
        "mip_feasibility_tolerance"=>1e-9,
        "mip_rel_gap"=>1e-9,
    )
    name=="Gurobi" && return optimizer_with_attributes(
        Gurobi.Optimizer,
        "Threads"=>1,
        "FeasibilityTol"=>1e-9,
        "OptimalityTol"=>1e-9,
        "IntFeasTol"=>1e-9,
        "MIPGap"=>1e-9,
        "DualReductions"=>0,
    )
    name=="Clarabel" && return Clarabel.Optimizer
    error("未声明求解器")
end

function transport_run(dir, group)
    group in ("open", "gurobi") || error("运行组错误")
    input, rule=transport_inputs(dir; current = true)
    todo=filter(r->(r["solver"]=="Gurobi") == (group=="gurobi"), input["records"])
    any(ispath(joinpath(dir, "records", r["id"])) for r in todo)&&error(
        "运行组已有记录；不覆盖或重开",
    )
    for item in todo
        c=R7RecoveryCase(item["case"])
        s=item["spec"]
        z=item["solver"]=="Clarabel" ? 1 .- item["fault"] : nothing
        r=solve_r7_transport_recovery(
            c,
            item["fault"],
            s;
            optimizer = transport_optimizer(item["solver"]),
            fixed_z = z,
            budget_sec = rule["budget_sec"],
        )
        save_r7_transport_recovery(c, s, r, joinpath(dir, "records", item["id"]))
        println(item["id"], " ", r["status"], " model=", r["validation"]["model_pass"])
    end
    println(group, " completed; all negative results retained.")
end

function transport_tables(dir)
    input, rule=transport_inputs(dir)
    summary=IOBuffer()
    witness=IOBuffer()
    paired=IOBuffer()
    println(
        summary,
        "record,group,flow,fault,solver,substeps,kind,run_id,status,model_pass,loss_electric_MWh,loss_heat_MWh,loss_MWh,lower_bound_MWh,conditional_optimality,elapsed_sec",
    )
    allruns=Dict{String,Any}()
    firstmodule=nothing
    for item in input["records"]
        x=transport_read(joinpath(dir, "records", item["id"]))
        x.case.sha256==item["case_sha256"] &&
        isequal(x.case.data, item["case"]) &&
        isequal(x.spec, item["spec"]) &&
        x.result["fault"]==item["fault"] || error("配对输入漂移")
        r=x.result
        q=x.validation
        allruns[item["id"]]=x
        r["source_hashes_at_solve"]==TOML.parsefile(joinpath(dir, "freeze.toml"))["science"] ||
            error("记录源码不同于预冻结")
        println(
            summary,
            join(
                [
                    item["id"],
                    item["group"],
                    item["flow_label"],
                    only(item["fault"]),
                    item["solver"],
                    x.spec["substeps"],
                    item["kind"],
                    r["run_id"],
                    r["status"],
                    q["model_pass"],
                    get(q, "loss_electric_MWh", ""),
                    get(q, "loss_heat_MWh", ""),
                    get(q, "loss_MWh", ""),
                    get(r, "lower_bound_MWh", ""),
                    q["conditional_optimality_pass"],
                    r["elapsed_sec"],
                ],
                ',',
            ),
        )
        firstmodule=TRANSPORT_MODULES[PaperRebuild.r7_digest(r["source_hashes_at_solve"])]
    end
    println(
        witness,
        "group,kind,node,step,scenario,flow_kg_s,target_MW,minimum_MW,maximum_MW,gap_MW,violated,S_node_lo_K,S_node_hi_K,R_node_lo_K,R_node_hi_K",
    )
    for source in input["sources"]
        c=Base.invokelatest(
            Base.invokelatest(getfield, firstmodule, :R7RecoveryCase),
            source["case"],
        )
        w=Base.invokelatest(
            Base.invokelatest(getfield, firstmodule, :r7_transport_port_witness),
            c,
            source["parent"],
            source["thermal_spec"],
        )
        isequal(w, source["witness"]) || error("输运区间证据重算不符")
        for row in w["rows"]
            fields=(
                "kind",
                "node",
                "step",
                "scenario",
                "flow_kg_s",
                "target_MW",
                "minimum_MW",
                "maximum_MW",
                "gap_MW",
                "violated",
                "S_node_lo_K",
                "S_node_hi_K",
                "R_node_lo_K",
                "R_node_hi_K",
            )
            println(witness, join(vcat([source["group"]], [row[k] for k in fields]), ','))
        end
    end
    println(paired, "group,flow,fault,comparison,relative_objective_difference,A2_value_pass")
    for group in rule["groups"], flow in rule["main_flows"], fault in (0, 1)
        a=allruns["$(group)_$(flow)_fault$(fault)_highs_n16"]
        b=allruns["$(group)_$(flow)_fault$(fault)_gurobi_n16"]
        both=a.validation["model_pass"]&&b.validation["model_pass"]
        diff=both ?
             abs(a.validation["loss_MWh"]-b.validation["loss_MWh"])/max(
            1,
            abs(a.validation["loss_MWh"]),
        ) : ""
        status=both ? "two_candidates" :
               a.result["status"]==b.result["status"]=="infeasible_certified" ?
               "two_conditional_infeasibilities" : "unresolved_comparison"
        println(paired, join([group, flow, fault, status, diff, both&&diff<=1e-4], ','))
    end
    Dict(
        "summary.csv"=>String(take!(summary)),
        "transport-witness.csv"=>String(take!(witness)),
        "solver-pairs.csv"=>String(take!(paired)),
    )
end

function transport_report(source, dest)
    ispath(dest)&&error("不覆盖输运报告")
    tables=transport_tables(source)
    cp(source, dest)
    for (p, t) in tables
        write(joinpath(dest, p), t)
    end
    write(
        joinpath(dest, "files.toml"),
        PaperRebuild.r7_text(Dict("files"=>transport_manifest(dest))),
    )
    println(
        "37 method records and original-state interval evidence archived without repeated optimization.",
    )
end

function transport_check(dir)
    transport_manifest(dir)==TOML.parsefile(joinpath(dir, "files.toml"))["files"] ||
        error("输运报告文件或哈希改变")
    for (p, t) in transport_tables(dir)
        read(joinpath(dir, p), String)==t || error("输运报告原值不符")
    end
    println(
        "37 frozen-source runs, interval witnesses, declared paired inputs and tables independently checked.",
    )
end

if abspath(PROGRAM_FILE)==@__FILE__
    if length(ARGS)==2 && ARGS[1]=="freeze"
        transport_freeze(abspath(ARGS[2]))
    elseif length(ARGS)==3 && ARGS[1]=="run"
        transport_run(abspath(ARGS[2]), ARGS[3])
    elseif length(ARGS)==3 && ARGS[1]=="report"
        transport_report(abspath(ARGS[2]), abspath(ARGS[3]))
    elseif length(ARGS)==2 && ARGS[1]=="check"
        transport_check(abspath(ARGS[2]))
    else
        error(
            "usage: r7_transport_study.jl freeze NEW | run FROZEN open|gurobi | report RAW NEW_REPORT | check REPORT",
        )
    end
end
