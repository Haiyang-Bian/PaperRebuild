# R6正式批次只追加新证据；临时文件不作为完成标志，重读不会调用求解器。
using Tar, UUIDs
const R6_STUDY_SCRIPT_FILES=[
    "scripts/r6_study.jl",
    "scripts/r6_study_io.jl",
    "scripts/r5_strategic_setup.jl",
    "scripts/r5_risk_setup.jl",
    "scripts/r5_market_setup.jl",
]

r6_study_hash(path) = bytes2hex(sha256(read(path)))
r6_study_text(x) = PaperRebuild.r5_market_text(x)
function r6_study_new(path, data)
    ispath(path) && error("不覆盖已有批次证据：$path")
    mkpath(dirname(path))
    temp=path*".writing-"*string(uuid4())
    write(temp, r6_study_text(data))
    ispath(path) && error("保存期间路径被创建")
    mv(temp, path)
    path
end

function r6_study_sources(root, spec)
    files=String[]
    for (dir, _, names) in walkdir(joinpath(root, "src")), name in names
        endswith(name, ".jl") &&
            push!(files, replace(relpath(joinpath(dir, name), root), '\\'=>'/'))
    end
    append!(
        files,
        vcat(
            R6_STUDY_SCRIPT_FILES,
            [
                "Project.toml",
                "Manifest.toml",
                "tools/solvers/Project.toml",
                "tools/solvers/Manifest.toml",
                "configs/r6/study.toml",
                "configs/r6/protocol.toml",
                "configs/r6/physical-rule.toml",
                spec.data["physical"],
            ],
        ),
    )
    sort!(unique!(files))
end

function r6_study_assert_sources(root, m)
    for (rel, hash) in m["sources"]
        r6_study_hash(joinpath(root, rel))==hash || error("批次执行源码改变：$(rel)；不得静默续用")
    end
end

# Git归档与磁盘哈希必须指向同一组原值，防止冻结期间的编辑造成版本混合。
function r6_study_check_archive(archive, sources)
    mktempdir() do dir
        Tar.extract(IOBuffer(archive), dir)
        actual=Dict{String,String}()
        for (folder, _, files) in walkdir(dir), file in files
            path=joinpath(folder, file)
            actual[replace(relpath(path, dir), '\\'=>'/')]=r6_study_hash(path)
        end
        actual==sources || error("源码归档与冻结文件清单不一致")
    end
    true
end

function r6_study_stress_set(spec, protocol)
    ids=String.(spec.data["stress_cases"])
    v=zeros(2, protocol.data["T"], 4)
    v[1, :, 3].=protocol.data["generator"]["clear_sky_fraction"]
    v[1, :, 4].=v[1, :, 3]
    v[2, :, 1].=1.0
    v[2, :, 2].=-1.0
    v[2, :, 3].=1.0
    v[2, :, 4].=-1.0
    hash=PaperRebuild.r6_trajectory_digest("stress", ids, v, protocol.sha256)
    (; ids, values = v, sha256 = hash)
end

r6_study_set(ctx, split) =
    split=="stress" ? r6_study_stress_set(ctx.spec, ctx.data.protocol) : ctx.data.sets[split]

function r6_study_summary(ctx, split, s, vals)
    if split=="stress"
        # 四个确定性边界日不是随机样本，不计算二项概率界或总体费用排名。
        return Dict{String,Any}(
            "schema"=>"r6-stress-summary-v1",
            "n"=>length(s.ids),
            "scope"=>"deterministic_cases_no_probability_claim",
            "cases"=>Dict(id=>v for (id, v) in zip(s.ids, vals)),
        )
    end
    r6_summarize_days(
        s.ids,
        vals;
        epsilon = ctx.spec.data["epsilon"],
        confidence = ctx.spec.data["confidence"],
    )
end

function freeze_r6_study(directory)
    VERSION==v"1.12.6" || error("Julia版本错误")
    ispath(directory) && error("不覆盖已冻结正式批次")
    root=normpath(joinpath(@__DIR__, ".."))
    spec=load_r6_study(joinpath(root, "configs", "r6", "study.toml"))
    files=r6_study_sources(root, spec)
    isempty(read(Cmd(vcat(["git", "-C", root, "diff", "HEAD", "--"], files)), String)) ||
        error("正式冻结前须提交科学代码和规则")
    success(
        pipeline(
            Cmd(vcat(["git", "-C", root, "ls-files", "--error-unmatch", "--"], files));
            stdout = devnull,
        ),
    ) || error("科学源码未追踪")
    dataset=read_r6_dataset(joinpath(root, spec.data["dataset"]))
    physical=load_r6_physical_case(joinpath(root, spec.data["physical"]))
    dataset.protocol.data["clustering"]["count"]==spec.data["training_support"] &&
    length(dataset.sets["validation"].ids)==spec.data["validation_days"] &&
    length(dataset.sets["test"].ids)==spec.data["test_days"] || error("正式数据规模与冻结规则不符")
    archive=read(Cmd(vcat(["git", "-C", root, "archive", "--format=tar", "HEAD", "--"], files)))
    length(archive)<=5*1024^2 || error("源码归档超出单文件限制")
    sources=Dict(f=>r6_study_hash(joinpath(root, f)) for f in files)
    r6_study_check_archive(archive, sources)
    cases=Dict{String,Any}()
    # 14项派生输入均先于首个优化构造，使用全训练支持，不传开发数量。
    for entry in r6_study_candidates(spec)
        c=r6_training_case(
            physical,
            dataset.protocol,
            dataset.sets["train"],
            dataset.representatives,
            R6MethodSpec(entry["method"]; radius = entry["radius"], epsilon = entry["epsilon"]),
        )
        cases[entry["id"]]=c
    end
    m=Dict{String,Any}(
        "schema"=>"r6-study-freeze-v1",
        "created_utc"=>string(now(UTC)),
        "source_commit"=>readchomp(`git -C $root rev-parse HEAD`),
        "julia_version"=>string(VERSION),
        "system"=>Dict(
            "kernel"=>string(Sys.KERNEL),
            "machine"=>Sys.MACHINE,
            "cpu"=>Sys.CPU_NAME,
            "cpu_threads"=>Sys.CPU_THREADS,
            "julia_threads"=>Threads.nthreads(),
            "memory_bytes"=>Sys.total_memory(),
        ),
        "spec"=>spec.data,
        "spec_sha256"=>spec.sha256,
        "physical_sha256"=>physical.sha256,
        "protocol_sha256"=>dataset.protocol.sha256,
        "sources"=>sources,
        "archive_sha256"=>bytes2hex(sha256(archive)),
        "data_manifest_sha256"=>r6_study_hash(
            joinpath(root, spec.data["dataset"], "manifest.toml"),
        ),
        "sets"=>Dict(k=>v.sha256 for (k, v) in dataset.sets),
        "cases"=>Dict{String,Any}(),
        "stress_sha256"=>r6_study_stress_set(spec, dataset.protocol).sha256,
        "status"=>"frozen_before_optimization",
    )
    r6_study_assert_sources(root, m)
    mkpath(directory)
    write(joinpath(directory, "source.tar"), archive)
    for entry in r6_study_candidates(spec)
        id=entry["id"]
        path=joinpath(directory, "inputs", id*".toml")
        r6_study_new(path, cases[id].data)
        m["cases"][id]=merge(
            entry,
            Dict("case_sha256"=>cases[id].sha256, "file_sha256"=>r6_study_hash(path)),
        )
    end
    r6_study_new(joinpath(directory, "freeze.toml"), m)
    write(
        joinpath(directory, "freeze.sha256"),
        r6_study_hash(joinpath(directory, "freeze.toml"))*"\n",
    )
    println("Frozen 14 complete-support inputs; no validation/test optimization performed.")
    m
end

function r6_study_open(directory; execution = false)
    root=normpath(joinpath(@__DIR__, ".."))
    r6_study_hash(joinpath(directory, "freeze.toml"))==strip(
        read(joinpath(directory, "freeze.sha256"), String),
    ) || error("批次冻结记录改变")
    m=TOML.parsefile(joinpath(directory, "freeze.toml"))
    m["schema"]=="r6-study-freeze-v1" || error("批次版本错误")
    s=R6StudySpec(m["spec"])
    s.sha256==m["spec_sha256"] || error("正式规则哈希不符")
    r6_study_hash(joinpath(directory, "source.tar"))==m["archive_sha256"] ||
        error("冻结源码归档改变")
    r6_study_check_archive(read(joinpath(directory, "source.tar")), m["sources"])
    execution && r6_study_assert_sources(root, m)
    for (id, c) in m["cases"]
        r6_study_hash(joinpath(directory, "inputs", id*".toml"))==c["file_sha256"] ||
            error("训练输入改变")
    end
    Set(keys(m["cases"]))==Set(x["id"] for x in r6_study_candidates(s)) || error("训练配置清单改变")
    data=read_r6_dataset(joinpath(root, s.data["dataset"]))
    r6_study_hash(joinpath(root, s.data["dataset"], "manifest.toml"))==m["data_manifest_sha256"] &&
    Dict(k=>v.sha256 for (k, v) in data.sets)==m["sets"] || error("输入数据不同")
    physical=load_r6_physical_case(joinpath(root, s.data["physical"]))
    physical.sha256==m["physical_sha256"] || error("共同物理边界改变")
    r6_study_stress_set(s, data.protocol).sha256==m["stress_sha256"] || error("压力轨迹改变")
    (; root, manifest = m, spec = s, data, physical)
end

function r6_study_solver(spec, which)
    which in ("gurobi", "highs") || error("未声明的正式求解器")
    # 使用已有求解器工厂并核对每项参数，不能在看到结果后隐式调整。
    f=which=="gurobi" ? r5_strategic_optimizer(:gurobi) : r5_market_optimizer(:highs)
    actual=Dict(x[1].name=>x[2] for x in f.params if x[1] isa MOI.RawOptimizerAttribute)
    actual==spec.data["solver_parameters"][which] || error("求解器参数与冻结规则不一致")
    f
end

function r6_study_training_record(directory, id, ctx)
    path=joinpath(directory, "training", id)
    r=read_r5_strategic_run(path)
    r.case.sha256==ctx.manifest["cases"][id]["case_sha256"] || error("训练案例不符")
    v=r.validation
    accepted=v["model_pass"]&&v["risk_pass"]&&v["cost_pass"]&&v["independent_market_kkt_pass"]
    entry=only(filter(x->x["id"]==id, r6_study_candidates(ctx.spec)))
    record=Dict{String,Any}(
        "candidate"=>entry,
        "case_sha256"=>r.case.sha256,
        "result_sha256"=>r6_study_hash(joinpath(path, "result.toml")),
        "run_id"=>r.result["run_id"],
        "status"=>r.result["status"],
        "candidate_accepted"=>accepted,
        "cost_optimization_complete"=>r.result["cost_optimization_complete"],
        "training_objective_USD"=>get(v, "worst_total_cost_USD", NaN),
        "elapsed_sec"=>r.result["elapsed_sec"],
    )
    policy=accepted ? r6_policy_from_training(ctx.physical, r.case, r.result) : nothing
    policy===nothing || (record["policy_sha256"]=policy.sha256)
    (; record, policy)
end

function r6_study_compact(v)
    keys=[
        "model_pass",
        "policy_complete",
        "cost_complete",
        "comfort_outcome",
        "trained_label",
        "peak_excess_K",
        "operating_net_cost",
        "day_ahead_cost",
        "device_cost",
        "real_time_settlement",
        "delivery_penalty",
        "called_energy_MWh",
        "mismatch_MWh",
        "mismatch_limit_MWh",
        "call_relative_mismatch",
        "delivery_budget_pass",
    ]
    Dict{String,Any}(k=>v[k] for k in keys if haskey(v, k))
end

function r6_study_day_read(path, policy, trajectory)
    w=TOML.parsefile(path)
    w["schema"]=="r6-study-day-v1" || error("逐日记录版本错误")
    r=w["result"]
    v=validate_r6_policy_day(policy, trajectory, r)
    PaperRebuild.r5_risk_validation_text(r6_study_compact(v))==PaperRebuild.r5_risk_validation_text(
        w["validation"],
    ) || error("逐日摘要与数值不一致")
    (; result = r, validation = w["validation"])
end

function r6_study_unknown()
    Dict{String,Any}(
        "model_pass"=>false,
        "policy_complete"=>false,
        "cost_complete"=>false,
        "comfort_outcome"=>"unknown",
    )
end

function r6_study_checked_summary(directory, split, candidate, ctx, trained)
    id=candidate["id"]
    folder=joinpath(directory, split, id)
    saved=TOML.parsefile(joinpath(folder, "summary.toml"))
    s=r6_study_set(ctx, split)
    saved["candidate"]==candidate&&saved["split"]==split&&saved["set_sha256"]==s.sha256 ||
        error("分组摘要身份不符")
    saved["training_result_sha256"]==trained.record["result_sha256"] || error("训练父记录不符")
    policy=trained.policy
    saved["training_candidate_accepted"]==(policy!==nothing) || error("训练候选资格不符")
    Set(keys(saved["days"]))==(policy===nothing ? Set{String}() : Set(s.ids)) ||
        error("逐日记录遗漏")
    if policy===nothing
        vals=[r6_study_unknown() for _ in s.ids]
    else
        vals=Dict{String,Any}[]
        for (i, day) in enumerate(s.ids)
            path=joinpath(folder, "days", day*".toml")
            r6_study_hash(path)==saved["days"][day] || error("分组日记录改变")
            w=TOML.parsefile(path)
            w["split"]==split&&w["candidate_id"]==id&&w["set_sha256"]==s.sha256 ||
                error("日记录来源改变")
            push!(vals, r6_study_day_read(path, policy, s.values[:, :, i]).validation)
        end
    end
    summary=r6_study_summary(ctx, split, s, vals)
    isequal(summary, saved["summary"]) || error("分组统计不能从逐日数值重建")
    saved
end
