# 只从既有运行提取数值见证；重复残差由冻结验证器重算，不重新求解。
module R9ReserveEvidence
using TOML, SHA, CSV, Dates, Test
include("r9_reserve_study.jl")
include("r9_fixed_evidence.jl")
include("r9_reserve_support.jl")
const Study=R9ReserveStudy
const Objects=R9FixedEvidence
hashfile(p) = bytes2hex(sha256(read(p)))
digest(s) = bytes2hex(sha256(IOBuffer(s)))
toml(p, x) = open(io->TOML.print(io, x; sorted = true), p, "w")
function table_parts(name, rows)
    isempty(rows) || return Objects.table_parts(name, rows)
    headers=Dict(
        :trajectories=>"method,run_id,t,P_DA_MW,R_up_MW,R_down_MW",
        :scenarios=>"method,run_id,scenario,probability,selected,actual_event,raw_event,comfort_excess_K,recourse_cost_CNY,delivery_mismatch_MWh,model_pass",
        :residuals=>"method,run_id,group,rows,maximum_normalized,worst_id,all_pass",
    )
    haskey(headers, name) || error("Unexpected empty table: $name")
    [string(name)*".csv"=>Vector{UInt8}(codeunits(headers[name]*"\n"))]
end
function extract(root, files, out)
    for (rel, h) in files
        p=Study.safe(out, rel)
        mkpath(dirname(p))
        write(p, Objects.bytes(root, h))
    end
end
function case_for(bundle, e)
    Study.call(
        bundle.lib,
        :r9_reserve_risk_case,
        bundle.template,
        bundle.dataset.sets["train"],
        bundle.dataset.representatives,
        bundle.spec,
        e["scheme"];
        pilot = e["pilot"],
    )
end
function tables(bundle, records)
    summaries, trajectories, scenarios, residuals, support=NamedTuple[],
    NamedTuple[],
    NamedTuple[],
    NamedTuple[],
    NamedTuple[]
    for (e, s, r, v) in records
        good=get(v, "model_pass", false) && get(v, "risk_pass", false)
        x=get(r, "first_stage", Dict{String,Any}())
        candidate=!isempty(x)
        capacities=candidate ? sum(x["R_up_MW"])+sum(x["R_down_MW"]) : NaN
        push!(
            summaries,
            (
                method = e["id"],
                scheme = e["scheme"],
                pilot = e["pilot"],
                scenarios = e["scenarios"],
                status = s["status"],
                run_id = get(r, "run_id", "none"),
                case_sha256 = e["case_sha256"],
                model_pass = get(v, "model_pass", false),
                risk_pass = get(v, "risk_pass", false),
                cost_pass = get(v, "cost_pass", false),
                optimality_pass = get(v, "optimality_pass", false),
                cost_optimization_complete = get(s, "cost_optimization_complete", false),
                budget_pass = s["budget_pass"],
                elapsed_sec = s["elapsed_sec"],
                empirical_cost_CNY = get(v, "nominal_net_cost", NaN),
                worst_cost_CNY = get(v, "worst_net_cost", NaN),
                empirical_event_probability = get(v, "nominal_violation_probability", NaN),
                worst_event_probability = get(v, "worst_violation_probability", NaN),
                selected_event_bound = get(v, "selected_violation_bound", NaN),
                relative_gap = get(v, "relative_gap", NaN),
                capacity_MW_h = capacities,
                accepted_in_adopted_model = good,
            ),
        )
        for t in 1:(candidate ? 24 : 0)
            push!(
                trajectories,
                (
                    method = e["id"],
                    run_id = r["run_id"],
                    t = t,
                    P_DA_MW = x["P_DA_MW"][t],
                    R_up_MW = x["R_up_MW"][t],
                    R_down_MW = x["R_down_MW"][t],
                ),
            )
        end
        groups=Dict{String,Vector{Any}}()
        add(rows) = foreach(q->push!(get!(groups, q["group"], Any[]), q), rows)
        add(get(v, "rows", []))
        case=case_for(bundle, e)
        original=case.data["commitment"]["scenarios"]
        p=[q["probability"] for q in original]
        D=Study.call(bundle.lib, :r5_market_array, case.data["ambiguity"]["distance"])
        for i in eachindex(original)
            upper=R9ReserveSupport.single_event_bound(p, D, case.data["ambiguity"]["radius"], i)
            push!(
                support,
                (
                    method = e["id"],
                    scenario = original[i]["id"],
                    probability = p[i],
                    worst_single_event = upper,
                    epsilon = case.data["epsilon"],
                    individually_allowed = upper<=case.data["epsilon"]+1e-8,
                ),
            )
        end
        for (i, sc) in enumerate(original)
            candidate || break
            z=v["scenarios"][sc["id"]]
            vv=z["validation"]
            add(vv["rows"])
            push!(
                scenarios,
                (
                    method = e["id"],
                    run_id = r["run_id"],
                    scenario = sc["id"],
                    probability = sc["probability"],
                    selected = r["z"][i],
                    actual_event = v["actual_event"][i],
                    raw_event = v["raw_event"][i],
                    comfort_excess_K = z["comfort_excess_K"],
                    recourse_cost_CNY = z["recourse_cost"],
                    delivery_mismatch_MWh = vv["mismatch_MWh"],
                    model_pass = vv["model_pass"],
                ),
            )
        end
        for group in sort(collect(keys(groups)))
            rows=groups[group]
            normalized(q) = abs(q["residual"])/q["tolerance"]
            worst=rows[argmax(normalized.(rows))]
            push!(
                residuals,
                (
                    method = e["id"],
                    run_id = get(r, "run_id", "none"),
                    group = group,
                    rows = length(rows),
                    maximum_normalized = normalized(worst),
                    worst_id = worst["id"],
                    all_pass = all(q["pass"] for q in rows),
                ),
            )
        end
    end
    (; summary = summaries, trajectories, scenarios, residuals, support)
end

"""封存全部原数值及原验收文本摘要；不把可重新生成的逐行残差重复写入公开包。"""
function freeze(study, batch, out)
    ispath(out) && error("Preserve previous evidence")
    carriers=(
        "r9_reserve_evidence.jl",
        "r9_fixed_evidence.jl",
        "r9_reserve_study.jl",
        "r9_reserve_support.jl",
    )
    carrier_hashes=Dict(name=>hashfile(joinpath(@__DIR__, name)) for name in carriers)
    bundle=Study.check(study)
    mkpath(joinpath(out, "objects"))
    index=Dict{String,Any}(
        "schema"=>"r9-reserve-evidence-v1",
        "origin"=>"synthetic",
        "created_utc"=>string(now(UTC)),
        "study_files"=>Objects.pack(out, study),
        "runs"=>Any[],
        "carrier"=>"raw_numerical_witness_with_recomputed_validation",
        "original_byte_files_retained_locally"=>true,
        "out_of_sample_completed"=>false,
    )
    records=[]
    for e in bundle.manifest["methods"]
        folder=joinpath(batch, e["id"])
        isdir(folder) || continue
        s=TOML.parsefile(joinpath(folder, "status.toml"))
        s["status"]!="started" || error("Method is still running")
        s["method_id"]==e["id"] || error("Method identity")
        z=Dict{String,Any}(
            "method_id"=>e["id"],
            "status_object"=>Objects.object(out, read(joinpath(folder, "status.toml"))),
        )
        r=Dict{String,Any}()
        v=Dict{String,Any}()
        if isdir(joinpath(folder, "run"))
            x=Study.call(bundle.lib, :read_r5_risk_run, joinpath(folder, "run"))
            x.case.sha256==e["case_sha256"] || error("Unexpected scientific input")
            r=deepcopy(x.result)
            v=x.validation
            z["validation_sha256"]=digest(Study.call(bundle.lib, :r5_risk_validation_text, v))
            z["original_result_sha256"]=hashfile(joinpath(folder, "run/result.toml"))
            # 原始变量、求解状态/界、独立运输见证全部保留；仅省去可重算的根验收表。
            delete!(r, "validation")
            z["witness_object"]=Objects.object(
                out,
                Vector{UInt8}(codeunits(Study.call(bundle.lib, :r5_market_text, r))),
            )
        else
            z["missing_run"]=true
        end
        push!(index["runs"], z)
        push!(records, (e, s, r, v))
    end
    length(records)==3 || error("Exactly three terminal methods are required")
    for (name, rows) in pairs(tables(bundle, records)), (file, content) in table_parts(name, rows)

        write(joinpath(out, file), content)
    end
    toml(joinpath(out, "index.toml"), index)
    for name in carriers
        hashfile(joinpath(@__DIR__, name))==carrier_hashes[name] ||
            error("Evidence source changed during archive")
        cp(joinpath(@__DIR__, name), joinpath(out, name))
    end
    write(
        joinpath(out, "README.md"),
        "# R9备用数值见证\n\n合成输入；完整轨迹补救与有限支持风险。无样本外认证。\n\n公开包保留所有原始变量、状态、界和运输见证；原逐行验收表由同一冻结验证器重算并核对规范文本SHA256。完整原字节文件仍在本地运行目录，不宣称本包是其逐字节镜像。\n\n从Julia项目环境执行 `julia +1.12.6 --startup-file=no --project=. PATH/r9_reserve_evidence.jl check PATH`，不调用求解器。\n",
    )
    files=Dict(p=>hashfile(Study.safe(out, p)) for p in Study.inventory(out))
    toml(joinpath(out, "artifact-hashes.toml"), Dict("files"=>files))
    println("Frozen three raw numerical witnesses and reproducible tables; no optimization.")
end

"""只读重建冻结输入和逐约束验收；认证保存数值，不重新求解或读取外部运行。"""
function check(out)
    h=TOML.parsefile(joinpath(out, "artifact-hashes.toml"))["files"]
    Set(Study.inventory(out))==union(Set(keys(h)), Set(["artifact-hashes.toml"])) ||
        error("Artifact inventory changed")
    for (p, v) in h
        hashfile(Study.safe(out, p))==v || error("Artifact changed: $p")
    end
    idx=TOML.parsefile(joinpath(out, "index.toml"))
    idx["schema"]=="r9-reserve-evidence-v1" &&
    idx["origin"]=="synthetic" &&
    !idx["out_of_sample_completed"] || error("Evidence scope")
    @testset "R9 reserve original numerical witnesses and frozen validation" begin
        mktempdir() do tmp
            extract(out, idx["study_files"], tmp)
            b=Study.check(tmp)
            records=[]
            @test length(idx["runs"])==3
            @test allunique(z["method_id"] for z in idx["runs"])
            for z in idx["runs"]
                e=only(e for e in b.manifest["methods"] if e["id"]==z["method_id"])
                s=Objects.parseobject(out, z["status_object"])
                @test s["case_sha256"]==e["case_sha256"]
                @test s["study_manifest_sha256"]==hashfile(joinpath(tmp, "manifest.toml"))
                c=case_for(b, e)
                @test c.sha256==e["case_sha256"]
                r=Dict{String,Any}()
                v=Dict{String,Any}()
                if haskey(z, "witness_object")
                    r=Objects.parseobject(out, z["witness_object"])
                    for (rel, h) in r["source_hashes_at_solve"]
                        @test b.manifest["files"]["code/"*rel]==h
                    end
                    v=Study.call(b.lib, :validate_r5_risk, c, r)
                    @test digest(Study.call(b.lib, :r5_risk_validation_text, v))==z["validation_sha256"]
                    for key in ("model_pass", "risk_pass", "cost_pass", "optimality_pass")
                        @test get(s, key, false)==v[key]
                    end
                    @test r["status"]==s["status"]
                    @test r["cost_optimization_complete"]==s["cost_optimization_complete"]
                end
                push!(records, (e, s, r, v))
            end
            for (name, rows) in pairs(tables(b, records)),
                (file, content) in table_parts(name, rows)

                @test read(joinpath(out, file))==content
            end
        end
    end
end
function main(args)
    length(args)==4 &&
        args[1]=="freeze" &&
        return freeze(abspath(args[2]), abspath(args[3]), abspath(args[4]))
    length(args)==2 && args[1]=="check" && return check(abspath(args[2]))
    error("usage: freeze STUDY BATCH NEW_ARCHIVE | check ARCHIVE")
end
end
if abspath(PROGRAM_FILE)==@__FILE__
    R9ReserveEvidence.main(ARGS)
end
