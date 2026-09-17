include("r3_setup.jl")
using CSV
length(ARGS)==1 || error("usage: audit_r3_baseline_history.jl OUTPUT_DIRECTORY")
dest=only(ARGS)
ispath(joinpath(dest, "historical-v3.csv")) && error("拒绝覆盖历史审计")
file="results/runs/r3-v3-20260917T115348-b8a7a604/study.toml"
study=TOML.parsefile(file)
rows=NamedTuple[]
traces=NamedTuple[]
for e in study["runs"]
    e["group"]=="ablation" && continue
    dir=normpath(joinpath(dirname(file), e["directory"]))
    meta=TOML.parsefile(joinpath(dir, "metadata.toml"))
    hash=open(sha256, joinpath(dir, "run.toml")) |> bytes2hex
    hash==meta["artifacts"]["run.toml"] || error("历史运行哈希不符")
    r=TOML.parsefile(joinpath(dir, "run.toml"))
    c=R2Case(TOML.parsefile(joinpath(dir, "case.toml")), meta["input_sha256"])
    # 审计已保存的历史轨迹与判定；不改写旧验证器含义、不重新求解。
    evidence=r3_stopping_evidence(c, r)
    for row in evidence
        push!(
            traces,
            (
                id = e["id"],
                iteration = row["iteration"],
                mode = row["mode"],
                cost = get(row, "cost", NaN),
                absolute_change = get(row, "absolute_change", NaN),
                epsilon_1e6 = get(row, "paper_form_epsilon_1.0e-6", false),
                epsilon_1e4 = get(row, "paper_form_epsilon_0.0001", false),
                epsilon_1e2 = get(row, "paper_form_epsilon_0.01", false),
                original_outer_status = r["outer_status"],
            ),
        )
    end
    push!(
        rows,
        (
            id = e["id"],
            run_sha256 = hash,
            input_sha256 = c.sha256,
            initial_flow_sha256 = get(r, "initial_flow_sha256", "none"),
            physical_pass = r["final_stage"]>0,
            outer_converged = r["outer_converged"],
            local_stationarity_checked = r["local_stationarity_checked"],
            iterations = length(get(r, "iterations", Any[])),
            outer_status = r["outer_status"],
            cost = r["final_stage"]>0 ? r["stages"][r["final_stage"]]["operating_cost"] : NaN,
        ),
    )
    println("AUDIT ", e["id"])
    flush(stdout)
    GC.gc()
end
length(rows)==24 || error("历史主实验不是24项")
CSV.write(joinpath(dest, "historical-v3.csv"), rows)
CSV.write(joinpath(dest, "historical-v3-stopping.csv"), traces)
println("24 historical v3 runs audited without rerunning optimization.")
