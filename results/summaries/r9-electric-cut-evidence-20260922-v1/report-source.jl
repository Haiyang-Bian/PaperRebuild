# 封存已选区域的必要供能界；父恢复及新证书均按冻结源码重读，不启动优化器。
module R9ElectricCutEvidence
using TOML, SHA, CSV, Dates
include("r9_resilience_evidence.jl")
const Archive = R9ResilienceEvidence
const Objects = Archive.Objects
const ROOT = dirname(@__DIR__)
hashfile(p) = bytes2hex(sha256(read(p)))
files(dir) = Dict(
    replace(relpath(joinpath(d, f), dir), '\\'=>'/')=>hashfile(joinpath(d, f)) for
    (d, _, names) in walkdir(dir) for f in names
)
toml(p, x) = open(io->TOML.print(io, x; sorted = true), p, "w")
function intact(dir)
    m=TOML.parsefile(joinpath(dir, "artifacts.toml"))["files"]
    actual=files(dir)
    delete!(actual, "artifacts.toml")
    actual==m || error("证据文件集合或字节改变")
    foreach(p->Archive.safe(dir, p), keys(m))
    m
end

# 从正常逐节点峰值和设备额定独立重算容量规则，不调用原r9_resilience_template。
function provenance(folder, event)
    construction=TOML.parsefile(joinpath(folder, "construction.toml"))
    p=TOML.parsefile(joinpath(folder, "capacity-protocol.toml"))
    hashfile(joinpath(folder, "capacity-protocol.toml"))==construction["protocol_sha256"] ||
        error("容量协议不是原冻结")
    for (name, hash) in construction["source_hashes"]
        hashfile(joinpath(folder, "source-"*name))==hash || error("来源副本不是原输入")
    end
    source=TOML.parsefile(joinpath(folder, "source-inputs.toml"))
    any(g->g["id"]=="R9-D01", source["gaps"]) || error("缺少电网参数缺口登记")
    top=TOML.parsefile(joinpath(folder, "source-topology.toml"))["electric"]["edges"]
    normal=TOML.parsefile(joinpath(folder, "normal.toml"))
    e=p["electric"]
    e["capacity_factor"]==1.5 &&
    e["design_rule"] ==
    "original_tree_absolute_load_and_all_connected_device_envelope; ties_use_path_sum_impedance_and_minimum_capacity" ||
        error("原容量构造规则改变")
    N=event["electric"]["nodes"]
    pe=[maximum(normal["electric"]["load_MW"][n]) for n in 1:N]
    for g in event["devices"]
        pe[g["electric_node"]]+=g["P_max_MW"]
    end
    order=[e["root"]]
    for i in order, edge in top
        edge[1]==i && push!(order, edge[2])
    end
    length(order)==N && length(unique(order))==N || error("原树不可遍历")
    for j in reverse(order[2:end])
        parent=only(x[1] for x in top if x[2]==j)
        pe[parent]+=pe[j]
    end
    caps=[e["capacity_factor"]*pe[x[2]] for x in top]
    ends=deepcopy(top)
    for tie in e["ties"]
        a, b=tie
        previous=Dict(a=>(0, 0))
        queue=[a]
        for i in queue, (l, (u, v)) in enumerate(top)
            j=u==i ? v : v==i ? u : 0
            if j!=0 && !haskey(previous, j)
                previous[j]=(i, l)
                push!(queue, j)
            end
        end
        path=Int[]
        j=b
        while j!=a
            j, l=previous[j]
            push!(path, l)
        end
        push!(caps, minimum(caps[l] for l in path))
        push!(ends, tie)
    end
    lines=event["electric"]["lines"]
    length(lines)==length(caps) || error("线路总数改变")
    errors=Float64[]
    for (l, x) in enumerate(lines)
        [x["from"], x["to"]]==ends[l] || error("原线路顺序改变")
        push!(errors, abs(x["P_max_MW"]-caps[l]))
    end
    maximum(errors)<=1e-10 || error("容量不符合冻结构造")
    Dict(
        "capacity_rule_verified"=>true,
        "maximum_capacity_error_MW"=>maximum(errors),
        "original_line_ratings_available"=>false,
        "gap_id"=>"R9-D01",
        "capacity_factor"=>e["capacity_factor"],
        "rule"=>e["design_rule"],
    )
end

function tables(folder)
    index=TOML.parsefile(joinpath(folder, "index.toml"))
    p=TOML.parsefile(joinpath(folder, "protocol.toml"))
    p["schema"]=="r9-electric-cut-study-v1" &&
    !p["optimization_performed"] &&
    !p["full_fault_certificate"] &&
    !p["original_data_complete"] || error("协议范围不符")
    root=isdir(joinpath(ROOT, "tmp")) ? joinpath(ROOT, "tmp") : tempdir()
    scratch=mktempdir(root; prefix = "r9-electric-cut-replay-", cleanup = false)
    Archive.extract(folder, index["parents"], joinpath(scratch, "parents"))
    certificates=Dict{String,Any}()
    summary=NamedTuple[]
    intervals=NamedTuple[]
    origins=Dict{String,Any}()
    for id in p["fault_ids"]
        old=Archive.frozen_read(joinpath(scratch, "parents", "aggregate-"*id))
        x=old.data
        x.validation["model_pass"] || error("本批父恢复未通过原模型检查")
        lib=Base.invokelatest(getfield, old.mod, :FrozenR7)
        Base.include(lib, joinpath(folder, "code", "r9_electric_cut.jl"))
        call(name, args...) = Base.invokelatest(Base.invokelatest(getfield, lib, name), args...)
        q=call(:r9_electric_cut_bound, x.case, x.result["fault"], p["nodes"])
        v=call(:validate_r9_electric_cut_bound, x.case, q)
        v["certificate_pass"] || error("割证书未通过")
        q["loss_lower_MWh"]<=x.result["solver_objective_MWh"]+1e-6 ||
            error("必要下界超过已知可行调度")
        certificates[id]=q
        origins[id]=provenance(folder, x.case.data)
        push!(
            summary,
            (
                fault = id,
                parent_run_id = x.result["run_id"],
                case_sha256 = x.case.sha256,
                original_status = x.result["status"],
                parent_model_pass = x.validation["model_pass"],
                lower_bound_MWh = q["loss_lower_MWh"],
                parent_loss_MWh = x.result["solver_objective_MWh"],
                limit_MWh = q["loss_limit_MWh"],
                threshold_excluded = q["threshold_excluded"],
                boundary_import_upper_MW = first(q["rows"])["boundary_import_upper_MW"],
                certificate_pass = v["certificate_pass"],
            ),
        )
        for row in q["rows"]
            push!(
                intervals,
                (
                    fault = id,
                    parent_run_id = x.result["run_id"],
                    time = row["time"],
                    scenario = row["scenario"],
                    hour = (x.case.data["event_start"]+row["time"]-2)*q["dt_h"],
                    dt_h = q["dt_h"],
                    probability = row["probability"],
                    critical_MW = row["critical_MW"],
                    internal_generation_upper_MW = row["internal_generation_upper_MW"],
                    boundary_import_upper_MW = row["boundary_import_upper_MW"],
                    loss_lower_MW = row["loss_lower_MW"],
                    weighted_energy_lower_MWh = row["weighted_energy_lower_MWh"],
                ),
            )
        end
    end
    encoded=Dict{String,Vector{UInt8}}(
        "summary.csv"=>Objects.csvbytes(summary),
        "intervals.csv"=>Objects.csvbytes(intervals),
    )
    for (name, data) in (("certificates.toml", certificates), ("provenance.toml", origins))
        io=IOBuffer()
        TOML.print(io, data; sorted = true)
        encoded[name]=take!(io)
    end
    encoded
end

function freeze(parent, out)
    ispath(out) && error("不覆盖网络割证据")
    intact(parent)
    original=TOML.parsefile(joinpath(parent, "index.toml"))
    original["schema"]=="r9-preplan-fault-evidence-v1" || error("父包类型错误")
    protocol=joinpath(ROOT, "configs/r9/electric-cut-study.toml")
    p=TOML.parsefile(protocol)
    stage=out*".writing"
    ispath(stage) && error("已有未完成封存")
    mkpath(joinpath(stage, "objects"))
    parents=Dict(
        k=>h for
        (k, h) in original["raw"] if any(id->startswith(k, "aggregate-"*id*"/"), p["fault_ids"])
    )
    for h in values(parents)
        Objects.object(stage, Objects.bytes(parent, h))==h || error("父原字节改变")
    end
    for (name, key) in (("construction.toml", "construction.toml"), ("normal.toml", "normal.toml"))
        write(joinpath(stage, name), Objects.bytes(parent, original["input"][key]))
    end
    construction=TOML.parsefile(joinpath(stage, "construction.toml"))
    rule=joinpath(ROOT, "configs/r9/resilience-protocol.toml")
    hashfile(rule)==construction["protocol_sha256"] || error("当前容量协议与原冻结不同")
    cp(rule, joinpath(stage, "capacity-protocol.toml"))
    for (name, hash) in construction["source_hashes"]
        file=joinpath(ROOT, "docs/reading/ch07", name)
        hashfile(file)==hash || error("当前来源与原冻结不同")
        cp(file, joinpath(stage, "source-"*name))
    end
    cp(protocol, joinpath(stage, "protocol.toml"))
    cp(joinpath(parent, "artifacts.toml"), joinpath(stage, "parent-artifacts.toml"))
    cp(joinpath(parent, "index.toml"), joinpath(stage, "parent-index.toml"))
    mkpath(joinpath(stage, "code"))
    cp(
        joinpath(ROOT, "src/verification/r9_electric_cut.jl"),
        joinpath(stage, "code/r9_electric_cut.jl"),
    )
    cp(@__FILE__, joinpath(stage, "report-source.jl"))
    for name in ("r9_resilience_evidence.jl", "r9_fixed_evidence.jl")
        cp(joinpath(@__DIR__, name), joinpath(stage, name))
    end
    toml(
        joinpath(stage, "index.toml"),
        Dict(
            "schema"=>"r9-electric-cut-evidence-v1",
            "parents"=>parents,
            "parent_artifacts_sha256"=>hashfile(joinpath(parent, "artifacts.toml")),
            "optimization_performed"=>false,
            "original_data_complete"=>false,
            "whole_fault_certificate"=>false,
        ),
    )
    for (name, bytes) in tables(stage)
        write(joinpath(stage, name), bytes)
    end
    toml(joinpath(stage, "artifacts.toml"), Dict("files"=>files(stage)))
    mv(stage, out)
    check(out; replay = true)
end

function check(folder; replay = false)
    hashes=intact(folder)
    index=TOML.parsefile(joinpath(folder, "index.toml"))
    index["schema"]=="r9-electric-cut-evidence-v1" &&
    !index["optimization_performed"] &&
    !index["original_data_complete"] &&
    !index["whole_fault_certificate"] || error("证据范围改变")
    hashfile(joinpath(folder, "parent-artifacts.toml"))==index["parent_artifacts_sha256"] ||
        error("父出处改变")
    parent=TOML.parsefile(joinpath(folder, "parent-index.toml"))
    all(parent["raw"][k]==h for (k, h) in index["parents"]) || error("父运行关联不符")
    if replay
        root=isdir(joinpath(ROOT, "tmp")) ? joinpath(ROOT, "tmp") : tempdir()
        scratch=mktempdir(root; prefix = "r9-electric-cut-frozen-", cleanup = false)
        relocated=joinpath(scratch, "evidence")
        cp(folder, relocated)
        m=Module(gensym(:FrozenCutReport))
        Base.include(m, joinpath(relocated, "report-source.jl"))
        lib=Base.invokelatest(getfield, m, :R9ElectricCutEvidence)
        fn=Base.invokelatest(getfield, lib, :tables)
        for (name, bytes) in Base.invokelatest(fn, relocated)
            bytes==read(joinpath(folder, name)) || error("冻结源码重算不同")
        end
        println("Electric cut relocated replay passed: ", relpath(scratch, ROOT))
    end
    println("Electric cut artifact hashes passed: ", length(hashes))
    true
end
end
if abspath(PROGRAM_FILE)==@__FILE__
    if length(ARGS)==3 && ARGS[1]=="freeze"
        R9ElectricCutEvidence.freeze(abspath.(ARGS[2:3])...)
    elseif length(ARGS) in (2, 3) && ARGS[1]=="check" && (length(ARGS)==2 || ARGS[3]=="--replay")
        R9ElectricCutEvidence.check(abspath(ARGS[2]); replay = length(ARGS)==3)
    else
        error(
            "usage: r9_electric_cut_evidence.jl freeze PARENT NEW_EVIDENCE | check EVIDENCE [--replay]",
        )
    end
end
