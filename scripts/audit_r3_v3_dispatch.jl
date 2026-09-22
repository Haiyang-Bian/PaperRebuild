using CSV, TOML, SHA

# 从已保存阶段表区分候选内层费用结束与严格原等式重调度；不修改旧字段、不求解。
length(ARGS)==2 || error("usage: audit_r3_v3_dispatch.jl STUDY_TOML SUMMARY_DIRECTORY")
studyfile, output=ARGS
study=TOML.parsefile(studyfile)
provenance=TOML.parsefile(joinpath(output, "provenance.toml"))["runs"]
rows=NamedTuple[]
for e in study["runs"]
    dir=normpath(joinpath(dirname(studyfile), e["directory"]))
    file=joinpath(dir, "run.toml")
    hash=bytes2hex(open(sha256, file))
    hash==only(x for x in provenance if x["id"]==e["id"])["run_sha256"] || error("运行哈希变化")
    prefix=String[]
    open(file) do io
        for line in eachline(io)
            startswith(line, "[") && break
            push!(prefix, line)
        end
    end
    header=TOML.parse(join(prefix, '\n'))
    meta=TOML.parsefile(joinpath(dir, "metadata.toml"))
    stages_path=joinpath(dir, "stages.csv")
    bytes2hex(open(sha256, stages_path))==meta["artifacts"]["stages.csv"] || error("阶段表哈希变化")
    stages=collect(CSV.File(stages_path))
    selected=header["final_stage"]>0 ? only(x for x in stages if x.stage==header["final_stage"]) :
             nothing
    attempts=[x for x in stages if x.stage in header["final_attempts"]]
    physical_costs=[x.operating_cost for x in attempts if x.physical_pass]
    push!(
        rows,
        (
            id = e["id"],
            run_sha256 = hash,
            selected_stage = header["final_stage"],
            selected_name = isnothing(selected) ? "none" : selected.name,
            selected_variant = isnothing(selected) ? "none" : selected.variant,
            selected_objective_kind = isnothing(selected) ? "none" : selected.objective_kind,
            candidate_inner_cost_complete = header["cost_optimization_complete"],
            selected_from_original_equality_model = !isnothing(selected) &&
                                                    selected.variant=="r3_fixed_physical_v1",
            original_equality_attempts = length(attempts),
            original_equality_A1_candidates = count(x.physical_pass for x in attempts),
            original_equality_statuses = join([x.status for x in attempts], ";"),
            best_original_equality_cost = isempty(physical_costs) ? missing :
                                          minimum(physical_costs),
        ),
    )
end
CSV.write(joinpath(output, "strict-dispatch-audit.csv"), rows)
println("逐例候选来源及原等式求解状态已核验，保留旧字段定义。")
