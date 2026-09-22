using PaperRebuild, TOML, CSV, SHA
args=filter(x->!startswith(x, "--"), ARGS)
length(args)==1||error("参数：共同承诺报告目录 [--seal] [--publish]")
dir=abspath(only(args))
root=normpath(joinpath(@__DIR__, ".."))
meta=TOML.parsefile(joinpath(dir, "report.toml"))
meta["schema"]=="r5-commitment-report-v1"&&meta["origin"]=="synthetic"&&!meta["solver_reexecuted"]||error(
    "共同承诺报告身份错误",
)
config=joinpath(root, "configs", "r5", "commitment", "study.toml")
rules=TOML.parsefile(config)
bytes2hex(sha256(read(config)))==meta["config_sha256"]||error("共同承诺规则变化")
for (rel, hash) in meta["source_sha256"]
    bytes2hex(sha256(read(joinpath(root, split(rel, '/')...))))==hash||error(
        "共同承诺科学源码变化：$rel",
    )
end
bytes2hex(sha256(read(joinpath(@__DIR__, "report_r5_commitment.jl"))))==meta["script_sha256"]||error(
    "共同承诺报告入口变化",
)
summary=collect(CSV.File(joinpath(dir, "comparison.csv")))
residuals=collect(CSV.File(joinpath(dir, "residuals.csv")))
commitments=collect(CSV.File(joinpath(dir, "commitments.csv")))
scenarios=collect(CSV.File(joinpath(dir, "scenarios.csv")))
trajectories=collect(CSV.File(joinpath(dir, "trajectories.csv")))
expected=Dict(x["id"]=>x for x in rules["runs"])
Set(x.record_id for x in summary)==Set(keys(expected))&&length(summary)==meta["records"]==22||error(
    "共同承诺记录范围错误",
)
close(x, y) = isequal(x, y)||(x isa Real&&y isa Real&&isapprox(x, y; atol = 1e-12, rtol = 1e-12))
for row in summary
    id=row.record_id
    e=expected[id]
    witness=TOML.parsefile(joinpath(dir, "witnesses", id*".toml"))
    c=R5CommitmentCase(witness["case"])
    r=witness["result"]
    v=validate_r5_commitment(c, r)
    c.sha256==row.case_sha256==load_r5_commitment_case(joinpath(dirname(config), e["case"])).sha256||error(
        "共同承诺见证输入错误",
    )
    witness["parent_result_sha256"]==meta["raw_result_sha256"][id]||error("共同承诺父记录错误")
    row.run_id==r["run_id"]&&row.case==e["case"]&&row.solver==e["solver"]&&row.status==r["status"]||error(
        "共同承诺身份改变",
    )
    all(
        getproperty(row, Symbol(k))==v[k] for
        k in ("model_pass", "cost_pass", "conditional_kkt_pass", "kkt_pass")
    )||error("共同承诺状态不同")
    row.cost_complete==r["cost_optimization_complete"]==(
        r["status"]=="solver_optimal"&&v["optimality_pass"]
    )||error("费用完成状态不同")
    for (field, key) in (
        (:objective, "expected_net_cost"),
        (:day_ahead_cost, "day_ahead_cost"),
        (:expected_recourse_cost, "expected_recourse_cost"),
        (:relative_gap, "relative_gap"),
    )
        close(getproperty(row, field), get(v, key, NaN))||error("共同费用数值不同")
    end
    close(row.bound, get(r, "solver_objective_bound", NaN))&&close(
        row.elapsed_sec,
        r["elapsed_sec"],
    )||error("费用界或预算不同")
    expected_rows=Dict{Tuple,Any}()
    for z in v["rows"]
        expected_rows[("shared", z["group"], z["id"], "shared", 0)]=z
    end
    for (sid, value) in v["scenarios"]
        for z in value["validation"]["rows"]
            expected_rows[(sid, z["group"], z["id"], z["entity"], z["t"])]=z
        end
        for z in value["kkt"]["rows"]
            expected_rows[(sid, "conditional_"*z["kind"], z["id"], "all", 0)]=z
        end
    end
    rr=filter(z->z.record_id==id, residuals)
    length(rr)==length(expected_rows)&&length(
        Set((z.scenario, z.group, z.id, z.entity, z.t) for z in rr),
    )==length(rr)||error("残差范围重复或不完整")
    for z in rr
        q=expected_rows[(z.scenario, z.group, z.id, z.entity, z.t)]
        z.run_id==row.run_id&&all(
            close(getproperty(z, Symbol(k)), q[k]) for
            k in ("residual", "normalized", "tolerance", "pass")
        )||error("共同承诺残差变化")
    end
    cc, ss, tt=(
        filter(z->z.record_id==id, table) for table in (commitments, scenarios, trajectories)
    )
    if !haskey(r, "first_stage")
        isempty(cc)&&isempty(ss)&&isempty(tt)||error("无候选伪造轨迹")
        continue
    end
    T=first(c.data["scenarios"])["case"]["T"]
    length(cc)==T&&Set(z.t for z in cc)==Set(1:T)||error("共同承诺轨迹不完整")
    for z in cc
        z.run_id==row.run_id&&all(
            close(getproperty(z, Symbol(k)), r["first_stage"][k][z.t]) for
            k in PaperRebuild.R5_COMMITMENT_KEYS
        )||error("共同承诺原值变化")
    end
    length(ss)==length(c.data["scenarios"])&&length(tt)==T*length(ss)||error("条件轨迹不完整")
    for s in c.data["scenarios"]
        sid=s["id"]
        z=only(filter(z->z.scenario==sid, ss))
        inner=v["scenarios"][sid]
        q=inner["validation"]
        z.run_id==row.run_id&&z.probability==s["probability"]&&z.model_pass==q["model_pass"]&&z.kkt_pass==inner["kkt"]["kkt_pass"]||error(
            "条件状态不同",
        )
        for (field, key) in (
            (:device_cost, "device_cost"),
            (:real_time_settlement, "real_time_settlement"),
            (:penalty, "delivery_penalty"),
            (:mismatch_MWh, "mismatch_MWh"),
            (:mismatch_limit_MWh, "mismatch_limit_MWh"),
        )
            close(getproperty(z, field), q[key])||error("条件费用/交付不同")
        end
        close(z.recourse_cost, inner["recourse_cost"])||error("条件补救费用不同")
        traj=filter(z->z.scenario==sid, tt)
        length(traj)==T&&Set(z.t for z in traj)==Set(1:T)||error("条件时域错误")
        for a in traj
            values=r["scenarios"][sid]["values"]
            a.run_id==row.run_id&&a.dt_h==s["case"]["dt_h"] &&
            close(a.P_actual_MW, values["P_PCC"][1][a.t])&&close(
                a.building_1_K,
                values["τ_IN"][1][a.t],
            )&&close(a.heat_1_MW, values["H_D"][1][a.t]) &&
            all(
                close(getproperty(a, Symbol(k)), q[k][a.t]) for
                k in ("request_MW", "delivered_MW", "mismatch_MW")
            )||error("条件物理轨迹变化")
        end
    end
end
length(residuals)==meta["residual_count"]&&close(
    maximum(z.normalized for z in residuals),
    meta["max_normalized_residual"],
)||error("残差汇总不同")
all(
    count(z->getproperty(z, Symbol(k)), summary)==meta[k] for
    k in ("model_pass", "kkt_pass", "cost_complete")
)||error("共同承诺汇总不同")
comparisons=collect(CSV.File(joinpath(dir, "solver-comparison.csv")))
length(comparisons)==12||error("求解器配对不完整")
for z in comparisons
    a=only(filter(x->x.record_id==z.reference, summary))
    b=only(filter(x->x.record_id==z.other, summary))
    z.case==a.case==b.case&&a.case_sha256==b.case_sha256||error("跨输入对照")
    comp=a.cost_complete&&b.cost_complete
    diff=comp ? abs(a.objective-b.objective)/max(1, abs(a.objective), abs(b.objective)) : NaN
    z.comparable==comp&&z.both_infeasible==(a.status==b.status=="solver_infeasible")&&close(
        z.objective_relative_difference,
        diff,
    )&&z.A2_pass==(comp&&diff<=1e-4)||error("A2配对变化")
end
if isfile(joinpath(dir, "figure-config.toml"))
    fig=TOML.parsefile(joinpath(dir, "figure-config.toml"))
    !fig["solver_reexecuted"]&&Set(fig["run_ids"])==Set(z.run_id for z in summary)||error(
        "共同承诺图源错误",
    )
    bytes2hex(sha256(read(joinpath(@__DIR__, "plot_r5_commitment.jl"))))==fig["script_sha256"]||error(
        "共同承诺绘图代码变化",
    )
    for (file, hash) in fig["sources"]
        bytes2hex(sha256(read(joinpath(dir, file))))==hash||error("共同承诺图源变化")
    end
end
hashes=Dict{String,String}()
for (base, _, files) in walkdir(dir), file in files
    file=="artifact-hashes.toml"&&continue
    path=joinpath(base, file)
    rel=replace(relpath(path, dir), '\\'=>'/')
    filesize(path)<5*1024^2||error("公共文件过大")
    if endswith(file, ".csv")||endswith(file, ".toml")
        occursin(r"(?i)[A-Z]:[\\/]|/Users/|/home/", read(path, String))&&error("公开摘要含本机路径")
    end
    hashes[rel]=bytes2hex(sha256(read(path)))
end
seal=joinpath(dir, "artifact-hashes.toml")
if "--seal" in ARGS
    ispath(seal)&&error("不覆盖共同承诺封存")
    write(seal, PaperRebuild.r5_market_text(Dict("sha256"=>hashes)))
else
    TOML.parsefile(seal)["sha256"]==hashes||error("共同承诺封存变化")
end
if "--publish" in ARGS
    target=joinpath(root, "docs", "src", "assets", "r5-commitment")
    for rel in vcat(collect(keys(hashes)), ["artifact-hashes.toml"])
        src=joinpath(dir, split(rel, '/')...)
        dst=joinpath(target, split(rel, '/')...)
        if ispath(dst)
            read(src)==read(dst)||error("不覆盖共同承诺文档资产")
        else
            mkpath(dirname(dst))
            cp(src, dst)
        end
    end
end
println(
    "Shared commitment artifacts: ",
    meta["model_pass"],
    "/",
    meta["records"],
    " model; independent physical/KKT/cost replay passed.",
)
