# 对已保存的事件全开CHP1候选独立评价六项恢复；不改变父计划或原4B最坏值。
const FAULT_STARTED=time()
using PaperRebuild, JuMP, Gurobi, TOML, SHA
include("r9_preplan_study.jl")
const PR=PaperRebuild

function main(input, parent, out)
    ispath(out) && error("不覆盖独立故障评价")
    x=R9PreplanStudy.readinput(input)
    c, p=x.case, x.protocol
    audit=TOML.parsefile(joinpath(parent, "audit.toml"))
    actual=R9PreplanStudy.filehashes(parent)
    delete!(actual, "audit.toml")
    actual==audit["files"] || error("父诊断字节改变")
    parentprotocol=TOML.parsefile(joinpath(parent, "protocol.toml"))
    parentprotocol["schema"]=="r9-preplan-loss-audit-v1" &&
    parentprotocol["input_manifest_sha256"]==R9PreplanStudy.hashfile(
        joinpath(input, "files.toml"),
    ) || error("父输入不是声明冻结")
    parentfile=joinpath(parent, "penalty_with_CHP1_event_on.toml")
    r=TOML.parsefile(parentfile)
    spec=TOML.parsefile(joinpath(input, "penalty-spec.toml"))
    check=PR.r7_planning_master_check(PR.r9_preplan_carrier(c, spec), r["master"])
    isequal(check, r["validation"]) && check["normal_pass"] && check["included_pass"] ||
        error("父候选未通过原检查")
    normal=r["master"]["normal"]
    sources=merge(R9PreplanStudy.science(), Dict("scripts/r9_preplan_faults.jl"=>@__FILE__))
    hashes=Dict(k=>R9PreplanStudy.hashfile(v) for (k, v) in sources)
    mkpath(out)
    for (k, v) in sources
        dest=joinpath(out, "code", k)
        mkpath(dirname(dest))
        cp(v, dest)
    end
    cp(parentfile, joinpath(out, "parent-result.toml"))
    cp(joinpath(parent, "protocol.toml"), joinpath(out, "parent-protocol.toml"))
    cp(joinpath(parent, "audit.toml"), joinpath(out, "parent-audit.toml"))
    for f in
        ("normal.toml", "planning.toml", "penalty-spec.toml", "files.toml", "construction.toml")
        cp(joinpath(input, f), joinpath(out, "input-"*f))
    end
    protocol=Dict(
        "schema"=>"r9-preplan-fault-evaluation-v1",
        "parent_file_sha256"=>R9PreplanStudy.hashfile(parentfile),
        "parent_run_id"=>r["run_id"],
        "normal_run_id"=>normal["run_id"],
        "input_manifest_sha256"=>R9PreplanStudy.hashfile(joinpath(input, "files.toml")),
        "source_hashes"=>hashes,
        "budget_sec"=>600.0,
        "recovery_deadline_sec"=>540.0,
        "stage_max_sec"=>60.0,
        "fault_ids"=>p["fault_ids"],
        "substeps"=>p["recovery_substeps"],
        "order"=>[kind*"-"*id for id in p["fault_ids"] for kind in ("aggregate", "detailed")],
        "preplan_optimization_performed"=>false,
        "whole_fault_claim"=>false,
        "physical_inputs_and_parent_values_unchanged"=>true,
    )
    write(joinpath(out, "protocol.toml"), PR.r7_text(protocol))
    event=PR.r7_planning_event(c, normal, 1)
    transport=R9PreplanStudy.transport(c, event, p)
    write(joinpath(out, "event.toml"), PR.r7_text(event.case.data))
    write(joinpath(out, "inheritance.toml"), PR.r7_text(event.evidence))
    write(joinpath(out, "transport-spec.toml"), PR.r7_text(transport))
    opt=optimizer_with_attributes(
        Gurobi.Optimizer,
        "OutputFlag"=>0,
        "Threads"=>1,
        "FeasibilityTol"=>1e-9,
        "IntFeasTol"=>1e-9,
        "OptimalityTol"=>1e-9,
        "MIPGap"=>1e-4,
    )
    rows=Any[]
    for (k, label) in enumerate(protocol["order"])
        kind, id=split(label, '-'; limit = 2)
        i=only(findall(==(id), p["fault_ids"]))
        fault=spec["pairs"][i]["fault"]
        start=time()
        allowance=max(0.0, min(60.0, (FAULT_STARTED+540-start)/(7-k)))
        if allowance==0
            push!(rows, Dict("stage"=>label, "attempted"=>false, "status"=>"budget_exhausted"))
            continue
        end
        println(label, " start budget=", allowance)
        flush(stdout)
        if kind=="aggregate"
            rec=solve_r7_recovery(
                event.case,
                fault;
                optimizer = opt,
                budget_sec = allowance,
                deadline = start+allowance,
            )
            save_r7_recovery(event.case, rec, joinpath(out, label))
        else
            rec=solve_r7_transport_recovery(
                event.case,
                fault,
                transport;
                optimizer = opt,
                budget_sec = allowance,
                deadline = start+allowance,
            )
            save_r7_transport_recovery(event.case, transport, rec, joinpath(out, label))
        end
        q=rec["validation"]
        push!(
            rows,
            Dict(
                "stage"=>label,
                "attempted"=>true,
                "status"=>rec["status"],
                "run_id"=>rec["run_id"],
                "model_pass"=>q["model_pass"],
                "loss_MWh"=>get(q, "loss_MWh", NaN),
                "elapsed_sec"=>time()-start,
                "budget_sec"=>allowance,
            ),
        )
        println(
            label,
            " ",
            rec["status"],
            " model=",
            q["model_pass"],
            " critical loss=",
            get(q, "loss_MWh", NaN),
        )
        flush(stdout)
    end
    all(R9PreplanStudy.hashfile(sources[k])==h for (k, h) in hashes) || error("运行期间源码改变")
    all(R9PreplanStudy.hashfile(joinpath(parent, k))==h for (k, h) in audit["files"]) ||
        error("父数据改变")
    write(
        joinpath(out, "execution.toml"),
        PR.r7_text(
            Dict(
                "stages"=>rows,
                "total_wall_sec"=>time()-FAULT_STARTED,
                "budget_pass"=>time()-FAULT_STARTED<=600,
                "whole_fault_claim"=>false,
            ),
        ),
    )
    write(joinpath(out, "files.toml"), PR.r7_text(Dict("files"=>R9PreplanStudy.filehashes(out))))
end
length(ARGS)==3 || error("usage: r9_preplan_faults.jl FROZEN_INPUT PARENT_LOSS_AUDIT NEW_OUTPUT")
main(abspath.(ARGS)...)
