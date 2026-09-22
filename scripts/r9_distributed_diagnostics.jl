# 固定热方向反例和目标报告差异：只读原值，封存与重验均不运行优化。
module R9DistributedDiagnostics
using TOML, SHA, CSV, JuMP
include("r9_distributed_study.jl")
include("r9_fixed_evidence.jl")
const S=R9DistributedStudy
const O=R9FixedEvidence
const ROOT=dirname(@__DIR__)

"""对事后选定区域逐项核查热量必要界，精确数按原Float64输入解释，不称最小不可行子集。"""
function heat_witness(d, m)
    h=d["heat"]
    p=h["pipes"]
    t=8
    region=setdiff(1:38, [5, 6, 23])
    d["T"]==24 && length(h["H_background_MW"])==38 || error("Witness input shape")
    R(x) = rationalize(BigInt, x; tol = 0)
    inside=[
        j for j in eachindex(p) if m["u_H"][j][1]==1&&p[j]["from"] in region&&p[j]["to"] in region
    ]
    cross=[
        j for
        j in eachindex(p) if m["u_H"][j][1]==1&&xor(p[j]["from"] in region, p[j]["to"] in region)
    ]
    cross==[9] && p[9]["from"]==24 && p[9]["to"]==5 || error("Witness boundary changed")
    all(j->m["heat_direction"][j][t]==1, [inside; cross]) ||
        error("Witness requires original fixed directions")
    maxsrc=R(0)
    minload=sum(R(h["H_background_MW"][i][t]) for i in region)
    terms=Dict{String,Any}[]
    for (j, g) in enumerate(d["devices"])
        g["heat_node"] in region || continue
        upper=g["kind"] in ("CHP", "P2H") ? R(g["availability_MW"][t])*R(g["heat_ratio"]) :
              g["kind"]=="HS" ? R(g["availability_MW"][t])*(1-m["z_storage"][j][t]) : R(0)
        maxsrc+=upper
        push!(terms, Dict("device"=>g["id"], "max_heat_MW"=>Float64(upper), "exact"=>string(upper)))
    end
    for a in d["actors"][2:end]
        a["heat_node"] in region || continue
        minload+=(1-R(a["flex"]))*R(a["H_load"][t])
    end
    h["delta_max_K"]>h["delta_min_K"]>0 || error("Temperature envelope changed")
    losses=sum(R(p[j]["loss_MW"]) for j in inside)
    exportmin=R(p[9]["loss_MW"])*R(h["delta_max_K"])/(R(h["delta_max_K"])-R(h["delta_min_K"]))
    gap=losses+exportmin-(maxsrc-minload)
    gap>0 || error("No strict contradiction")
    Dict(
        "nodes"=>region,
        "t"=>t,
        "boundary_pipe"=>9,
        "sources"=>terms,
        "maximum_source_MW"=>Float64(maxsrc),
        "minimum_load_MW"=>Float64(minload),
        "maximum_net_supply_MW"=>Float64(maxsrc-minload),
        "internal_loss_MW"=>Float64(losses),
        "minimum_boundary_export_MW"=>Float64(exportmin),
        "gap_MW"=>Float64(gap),
        "gap_exact"=>string(gap),
        "posthoc_region"=>true,
        "scope"=>"fixed_mode_thermal_envelope_only",
    )
end

function point(b, s)
    values=Dict{VariableRef,Float64}()
    for (key, vars) in b.variables
        numbers=ndims(vars)==1 ? Float64.(s[key]) : reduce(vcat, permutedims.(s[key]))
        size(numbers)==size(vars) || error("Saved variable dimensions")
        for i in eachindex(vars)
            values[vars[i]]=numbers[i]
        end
    end
    length(values)==num_variables(b.model) || error("Missing original variables")
    values
end

function objective_rows(lib, c, raw)
    length(raw["trace"])==1 && raw["input_sha256"]==c.sha256 || error("First-iteration identity")
    row=only(raw["trace"])
    rows=NamedTuple[]
    for saved in [row["agents"]; row["operator"]]
        b=S.call(lib, :build_r9_distributed_block, c; actor = saved["actor"])
        target=b.actor==1 ? S.call(lib, :r4_matrix, row["x"]) : zeros(size(b.message))
        S.call(
            lib,
            :r9_distributed_objective!,
            b,
            target,
            zeros(size(target)),
            raw["cost_scale"],
            raw["rho"],
        )
        p=point(b, saved["values"])
        obj=objective_function(b.model)
        expanded=value(v->p[v], obj)
        precise=BigFloat(obj.aff.constant) +
                sum(BigFloat(a)*BigFloat(p[v]) for (a, v) in linear_terms(obj.aff); init = big"0") +
                sum(
                    BigFloat(a)*BigFloat(p[v])*BigFloat(p[w]) for (a, v, w) in quad_terms(obj);
                    init = big"0",
                )
        cost=S.call(lib, :r9_distributed_block_cost, c, saved)
        message=S.call(lib, :r4_matrix, saved["message"])
        stable=cost/raw["cost_scale"]+raw["rho"]/2*sum(
            abs2,
            message ./ reshape(b.contract.scale[b.rows], :, 1)-target,
        )
        abs(expanded-stable)<=1e-10*max(1, abs(stable)) &&
        abs(precise-BigFloat(stable))<=big"1e-10"*max(1, abs(precise)) ||
            error("Objective algebra differs")
        reported=saved["augmented_objective"]
        scale=max(1.0, abs(reported), abs(stable))
        push!(
            rows,
            (;
                actor = b.actor,
                reported,
                expanded,
                stable,
                bigfloat = string(precise),
                report_error = reported-stable,
                report_gate = 1e-9*scale,
                report_pass = abs(reported-stable)<=1e-9*scale,
                model_class = b.model_class,
            ),
        )
    end
    rows
end

function native_rows(lib, c, root)
    rows=NamedTuple[]
    for label in ("default", "precision")
        report=TOML.parsefile(joinpath(root, "native-"*label*"-audit.toml"))
        s=TOML.parsefile(joinpath(root, "native-"*label*"-values.toml"))
        b=S.call(lib, :build_r9_distributed_block, c; actor = 4)
        C=S.call(lib, :r9_distributed_cost_scale, c)
        S.call(
            lib,
            :r9_distributed_objective!,
            b,
            zeros(size(b.message)),
            zeros(size(b.message)),
            C,
            1.0,
        )
        p=point(b, s)
        evaluated=value(v->p[v], objective_function(b.model))
        for key in ("native_evaluated", "original_evaluated", "stable_evaluated")
            abs(evaluated-report[key])<=1e-10*max(1, abs(evaluated)) ||
                error("Native objective replay differs")
        end
        report["jump_reported"]==report["native_reported"]==report["native_ObjVal"] ||
            error("Reported return path changed")
        difference=report["native_reported"]-evaluated
        push!(
            rows,
            (;
                probe = label,
                termination = report["termination"],
                solver_version = report["solver_version"],
                reported = report["native_reported"],
                evaluated,
                difference,
                report_pass = abs(difference)<=1e-9*max(
                    1.0,
                    abs(evaluated),
                    abs(report["native_reported"]),
                ),
                original_gate_status_pass = report["termination"]=="OPTIMAL",
                reported_bound = report["native_ObjBound"],
                barrier_iterations = report["native_BarIterCount"],
            ),
        )
    end
    rows
end

function replay(root)
    raw=TOML.parsefile(joinpath(root, "raw-first-iteration.toml"))
    for (rel, h) in raw["source_hashes_at_solve"]
        S.hashfile(joinpath(root, "snapshot", rel))==h || error("Original science hash differs")
    end
    lib=S.library(joinpath(root, "snapshot"))
    c=S.call(lib, :load_r9_trading_case, joinpath(root, "input.toml"))
    d=TOML.parsefile(joinpath(root, "input.toml"))
    m=TOML.parsefile(joinpath(root, "fixed-modes.toml"))
    (;
        heat = heat_witness(d, m),
        objectives = objective_rows(lib, c, raw),
        native = native_rows(lib, c, root),
    )
end

"""封存原字节、冻结实现及可移位重读诊断；不给旧运行补造缺失迭代。"""
function archive(study, probe, native_default, native_precision, out)
    ispath(out) && error("Do not overwrite diagnostics")
    raw=TOML.parsefile(joinpath(probe, "raw-before-validation.toml"))
    for (rel, h) in raw["source_hashes_at_solve"]
        S.hashfile(joinpath(study, "code", rel))==h || error("Study/probe science differs at "*rel)
    end
    mkpath(joinpath(out, "objects"))
    files=Dict{String,String}()
    add(rel, path) = (files[rel]=O.object(out, read(path)))
    add("input.toml", joinpath(probe, "input.toml"))
    add("fixed-modes.toml", joinpath(study, "fixed-modes.toml"))
    add("raw-first-iteration.toml", joinpath(probe, "raw-before-validation.toml"))
    for (label, folder) in (("default", native_default), ("precision", native_precision))
        for name in ("audit", "values")
            add("native-"*label*"-"*name*".toml", joinpath(folder, name*".toml"))
        end
        add("native-"*label*"-bridges.txt", joinpath(folder, "bridges.txt"))
    end
    for rel in keys(raw["source_hashes_at_solve"])
        add("snapshot/"*rel, joinpath(study, "code", rel))
    end
    meta=Dict(
        "schema"=>"r9-distributed-diagnostics-v1",
        "origin"=>"synthetic",
        "solver_used_for_replay"=>false,
        "scope"=>"fixed-mode contradiction and first-iteration/native-scalar diagnosis; not full distributed validation",
        "study_manifest_sha256"=>S.hashfile(joinpath(study, "manifest.toml")),
        "files"=>files,
    )
    derived=Dict{String,String}()
    mktempdir() do folder
        restore(out, files, folder)
        data=replay(folder)
        S.toml(joinpath(out, "heat-witness.toml"), data.heat)
        for name in (:objectives, :native)
            write(joinpath(out, string(name)*".csv"), O.csvbytes(getproperty(data, name)))
        end
    end
    for rel in ("heat-witness.toml", "objectives.csv", "native.csv")
        derived[rel]=S.hashfile(joinpath(out, rel))
    end
    for rel in (
        "scripts/r9_distributed_diagnostics.jl",
        "scripts/r9_distributed_study.jl",
        "scripts/r9_trading_study.jl",
        "scripts/r9_fixed_evidence.jl",
    )
        target=joinpath(out, "code", rel)
        mkpath(dirname(target))
        cp(joinpath(ROOT, rel), target)
        derived["code/"*rel]=S.hashfile(target)
    end
    meta["derived_files"]=derived
    S.toml(joinpath(out, "evidence.toml"), meta)
    println("Archived fixed-mode proof and objective diagnostics; no optimization.")
end

function restore(out, files, root)
    for (rel, h) in files
        path=S.safe(root, rel)
        mkpath(dirname(path))
        write(path, O.bytes(out, h))
    end
end

"""核对清单、重新推导精确热量界，并从冻结科学代码/原变量重算数学目标。"""
function check(out)
    m=TOML.parsefile(joinpath(out, "evidence.toml"))
    m["schema"]=="r9-distributed-diagnostics-v1"&&m["origin"]=="synthetic"&&!m["solver_used_for_replay"] ||
        error("Diagnostic scope")
    for (rel, h) in m["derived_files"]
        S.hashfile(S.safe(out, rel))==h || error("Derived diagnostic bytes changed")
    end
    mktempdir() do folder
        restore(out, m["files"], folder)
        data=replay(folder)
        data.heat==TOML.parsefile(joinpath(out, "heat-witness.toml")) || error("Witness changed")
        for name in (:objectives, :native)
            O.csvbytes(getproperty(data, name))==read(joinpath(out, string(name)*".csv")) ||
                error("Objective diagnostics changed")
        end
    end
    println("Exact thermal witness and frozen objective replay passed; no optimization.")
    true
end

if abspath(PROGRAM_FILE)==abspath(@__FILE__)
    if length(ARGS)==6 && ARGS[1]=="archive"
        archive(abspath.(ARGS[2:end])...)
    elseif length(ARGS)==2 && ARGS[1]=="check"
        check(abspath(ARGS[2]))
    else
        error(
            "usage: r9_distributed_diagnostics.jl archive FIXED_STUDY FIRST_PROBE DEFAULT_PROBE PRECISION_PROBE NEW_OUTPUT | check OUTPUT",
        )
    end
end
end
