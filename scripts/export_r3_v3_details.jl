using TOML, CSV, SHA, PaperRebuild

# 正式报告已完成全量独立验证；本脚本核对同一运行哈希后仅导出候选、驻点和末次调度摘要。
length(ARGS)==2 || error("usage: export_r3_v3_details.jl STUDY_TOML SUMMARY_DIRECTORY")
studyfile, output=ARGS
study=TOML.parsefile(studyfile)
provenance=TOML.parsefile(joinpath(output, "provenance.toml"))["runs"]
candidates=NamedTuple[]
finals=NamedTuple[]
stationarity=NamedTuple[]
tail_audit=NamedTuple[]

# 固定CT与保存流量，按有向树因果回放；不使用保存的下游供水温度当边界。
function ct_tail_rows(c, s, id, stage, role)
    h=c.data["heat"]
    o=PaperRebuild.r3_operation_from_dict(s["operation"])
    v=deepcopy(s["values"])
    all(e["from"]<e["to"] for e in h["pipes"]) || error("该审计需要明确的上游编号顺序")
    for t in 1:c.data["T"], j in eachindex(h["nodes"])
        node=h["nodes"][j]
        incoming=[
            (v["m_pipe"][p][t], v["tau_S_out"][p][t]) for
            (p, e) in enumerate(h["pipes"]) if e["to"]==j
        ]
        node["role"]=="source" && push!(incoming, (v["m_port"][j][t], o.source_temperature_K))
        mix=sum(m*T for (m, T) in incoming)/sum(first, incoming)
        v["tau_S_mix"][j][t]=mix
        v["tau_S_port"][j][t]=node["role"]=="source" ? o.source_temperature_K : mix
        for (p, e) in enumerate(h["pipes"])
            e["from"]==j || continue
            v["tau_S_in"][p][t]=mix
            replay=PaperRebuild.r3_mass_replay(c, v, p, t, "S")
            v["tau_S_star"][p][t]=replay.star
            v["tau_S_out"][p][t]=replay.out
        end
    end
    return [
        (;
            id,
            stage,
            role,
            node = j,
            time_h = t*c.data["dt_h"],
            supply_K = v["tau_S_port"][j][t],
            fixed_return_K = n["return_K"],
            required_MW = n["H_MW"][t],
            causal_heat_MW = h["cp_J_kgK"]/1e6*v["m_port"][j][t]*(
                v["tau_S_port"][j][t]-n["return_K"]
            ),
            mismatch_MW = h["cp_J_kgK"]/1e6*v["m_port"][j][t]*(v["tau_S_port"][j][t]-n["return_K"])-n["H_MW"][t],
        ) for (j, n) in enumerate(h["nodes"]) for
        t in (o.core_periods+1):c.data["T"] if n["role"]=="load"
    ]
end
for id in (
    "two-source-schpd",
    "two-source-VF_CT-pg",
    "single-delay-switch",
    "single-loose-electric",
    "two-source-VF_CT-pg-without-physical-recovery",
    "two-source-schpd-without-stationarity-check",
)
    entry=only(x for x in study["runs"] if x["id"]==id)
    path=normpath(joinpath(dirname(studyfile), entry["directory"], "run.toml"))
    bytes2hex(sha256(read(path)))==only(x for x in provenance if x["id"]==id)["run_sha256"] ||
        error("运行哈希不同")
    r=TOML.parsefile(path)
    c=load_r2_case(joinpath(dirname(path), "case.toml"))
    for b in get(r, "candidate_bank", Any[])
        s=r["stages"][b["stage"]]
        reconstructed=PaperRebuild.r3_v3_reconstruct(c, s)
        review=validate_r3_solution(c, reconstructed)
        push!(
            candidates,
            (
                id,
                stage = b["stage"],
                roles = join(b["roles"], ";"),
                flow_sha256 = b["flow_sha256"],
                cost = s["operating_cost"],
                model_pass = s["model_pass"],
                raw_physical_pass = s["physics_pass"],
                reconstructed_physical_pass = review.physical_pass,
                maximum_normalized_violation = PaperRebuild.r3_physical_score(c, reconstructed),
            ),
        )
    end
    for i in get(r, "final_attempts", Int[])
        s=r["stages"][i]
        push!(
            finals,
            (
                id,
                stage = i,
                status = s["status"],
                termination = get(s, "termination", ""),
                model_pass = s["model_pass"],
                physical_pass = s["physics_pass"],
                operating_cost = get(s, "operating_cost", missing),
                selected = i==r["final_stage"],
            ),
        )
    end
    for (j, p) in enumerate(get(get(r, "stationarity_check", Dict()), "probes", Any[]))
        s=r["stages"][p["stage"]]
        l=p["local"]
        push!(
            stationarity,
            (
                id,
                probe = j,
                stage = p["stage"],
                cost = s["operating_cost"],
                checked = r["local_stationarity_checked"],
                direction = l["direction_norm"],
                trust_binding = l["trust_binding"],
                kkt_trusted = l["kkt"]["trusted"],
                predicted_merit = l["predicted_merit"],
                switches = join(l["switches"], ";"),
            ),
        )
    end
    if id=="two-source-VF_CT-pg"
        first_stage=first(r["candidate_bank"])["stage"]
        append!(
            tail_audit,
            ct_tail_rows(c, r["stages"][first_stage], id, first_stage, "before_restoration"),
        )
        if r["final_stage"]>0
            append!(
                tail_audit,
                ct_tail_rows(
                    c,
                    r["stages"][r["final_stage"]],
                    id,
                    r["final_stage"],
                    "retained_A1_candidate",
                ),
            )
        end
    end
    println("DETAIL ", id)
    GC.gc()
end
CSV.write(joinpath(output, "candidate-bank.csv"), candidates)
CSV.write(joinpath(output, "final-attempts.csv"), finals)
CSV.write(joinpath(output, "stationarity-probes.csv"), stationarity)
CSV.write(joinpath(output, "fixed-flow-tail-audit.csv"), tail_audit)

# 直接检验已保存CF-CT候选在较自由VF-CT域中的嵌入，不重新求解、不作为PG初值。
entry=only(x for x in study["runs"] if x["id"]=="two-source-CF_CT-pg")
path=normpath(joinpath(dirname(studyfile), entry["directory"], "run.toml"))
hash=bytes2hex(sha256(read(path)))
hash==only(x for x in provenance if x["id"]==entry["id"])["run_sha256"] || error("嵌入来源哈希不同")
r=TOML.parsefile(path)
c=load_r2_case(joinpath(dirname(path), "case.toml"))
s=deepcopy(r["stages"][r["final_stage"]])
s["operation"]=PaperRebuild.r3_operation_dict(R3OperationSpec(c; mode = :VF_CT))
s["operation_sha256"]=PaperRebuild.r3_operation_hash(s["operation"])
v=validate_r3_solution(c, s)
open(
    io->TOML.print(
        io,
        Dict(
            "scope"=>"independent_embedding_check_no_optimization_or_PG_seeding",
            "source_id"=>entry["id"],
            "source_run_sha256"=>hash,
            "input_sha256"=>c.sha256,
            "source_mode"=>"CF_CT",
            "target_mode"=>"VF_CT",
            "model_pass"=>v.model_pass,
            "physical_pass"=>v.physical_pass,
            "operating_cost"=>s["operating_cost"],
            "maximum_normalized_violation"=>PaperRebuild.r3_physical_score(c, s),
        );
        sorted = true,
    ),
    joinpath(output, "mode-embedding.toml"),
    "w",
)

audit=joinpath(dirname(output), "audit")
manifest=TOML.parsefile(joinpath(audit, "manifest.toml"))
bytes2hex(sha256(read(joinpath(audit, "failure.toml"))))==manifest["files"]["failure.toml"] ||
    error("参考快照哈希不同")
reference=TOML.parsefile(joinpath(audit, "failure.toml"))["reference_final"]
reference["v3_physical_review"]=true
v=validate_r3_solution(c, reference)
open(
    io->TOML.print(
        io,
        Dict(
            "scope"=>"independent_saved_reference_recheck_only",
            "used_for_PG_initialization"=>false,
            "reoptimized"=>false,
            "source_snapshot_sha256"=>manifest["files"]["failure.toml"],
            "input_sha256"=>c.sha256,
            "operating_cost"=>reference["operating_cost"],
            "model_pass"=>v.model_pass,
            "physical_pass_with_v3_delivered_load_check"=>v.physical_pass,
            "maximum_normalized_violation"=>PaperRebuild.r3_physical_score(c, reference),
        );
        sorted = true,
    ),
    joinpath(output, "reference-recheck.toml"),
    "w",
)
