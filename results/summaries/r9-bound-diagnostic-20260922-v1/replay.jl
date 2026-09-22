# R9连续首块的有限等价表示诊断：读取数值多项式，不加载优化器或重跑调度。
module R9BlockBoundEvidence
using TOML, SHA, LinearAlgebra

hashfile(path) = bytes2hex(open(sha256, path))
readtoml(path) = TOML.parsefile(path)
write_toml(path, data) = open(io->TOML.print(io, data; sorted = true), path, "w")

"""对已保存二次多项式求值与求导，平方项的两次贡献均保留。"""
function polynomial(p, x)
    value=p["constant"]
    gradient=zeros(length(x))
    for (i, a) in zip(p["linear_ids"], p["linear_coefficients"])
        value+=a*x[i]
        gradient[i]+=a
    end
    for (i, j, a) in zip(p["quadratic_i"], p["quadratic_j"], p["quadratic_coefficients"])
        value+=a*x[i]*x[j]
        gradient[i]+=a*x[j]
        gradient[j]+=a*x[i]
    end
    value, gradient
end

"""原旋转锥经正交变换为SOC；原始点与原始对偶使用相同坐标和内积。"""
function cone_error(kind, z)
    if kind=="soc"
        return max(0.0, norm(z[2:end])-z[1])
    elseif kind=="rsoc"
        return max(0.0, norm([(z[1]-z[2])/sqrt(2); z[3:end]])-(z[1]+z[2])/sqrt(2))
    end
    error("Unknown cone")
end

"""
    replay(model_snapshot, witness)

从数字系数、原点和未修改乘子重算残差。归一化沿用R3检查形式，补旋转锥。
指标是数值诊断，不是A1替代品或严格全局下界；求解器状态及旧验收不变。
缺失乘子使对偶、互补、驻点指标不可用，不能按零误差处理。
"""
function replay(s, w)
    x=w["x"]
    length(x)==length(s["variables"]) && all(isfinite, x) || error("Invalid point")
    value, station=polynomial(s["objective"], x)
    denominator=1 .+ abs.(station)
    duals=get(w, "raw_duals", Dict{String,Any}())
    complete=all(r->haskey(duals, r["id"]), s["constraints"])
    pe, rawpe, de, ce=0.0, 0.0, 0.0, 0.0
    worst=""
    for row in s["constraints"]
        evaluations=[polynomial(p, x) for p in row["functions"]]
        z=first.(evaluations)
        kind=row["kind"]
        slack=kind in ("equal", "lower", "upper") ? z .- row["rhs"] : z
        p=if kind=="equal"
            abs(slack[1])
        elseif kind=="lower"
            max(0.0, -slack[1])
        elseif kind=="upper"
            max(0.0, slack[1])
        else
            cone_error(kind, z)
        end
        rawpe=max(rawpe, p)
        normalized=p/max(1.0, norm(z), norm(slack))
        if normalized>pe
            pe=normalized
            worst=row["id"]
        end
        if haskey(duals, row["id"])
            y=duals[row["id"]]
            length(y)==length(z) && all(isfinite, y) || error("Invalid multiplier")
            d=kind=="equal" ? 0.0 :
              kind=="lower" ? max(0.0, -y[1]) : kind=="upper" ? max(0.0, y[1]) : cone_error(kind, y)
            de=max(de, d/max(1.0, norm(y)))
            ce=max(ce, abs(dot(slack, y))/max(1.0, norm(slack)*norm(y)))
            for ((_, gradient), yi) in zip(evaluations, y)
                contribution=yi .* gradient
                station.-=contribution
                denominator.+=abs.(contribution)
            end
        end
    end
    report=w["reported_objective"]
    Dict(
        "objective_at_primal"=>value,
        "report_relative_error"=>abs(report-value)/max(1, abs(report), abs(value)),
        "primal_normalized"=>pe,
        "primal_raw_mixed_units"=>rawpe,
        "worst_primal_row"=>worst,
        "all_raw_duals_available"=>complete,
        "dual_normalized"=>complete ? de : NaN,
        "complementarity_normalized"=>complete ? ce : NaN,
        "stationarity_normalized"=>complete ? maximum(abs.(station) ./ denominator) : NaN,
        "global_bound_certified"=>false,
        "diagnostic_only"=>true,
    )
end

function signature(row)
    io=IOBuffer()
    TOML.print(io, Dict(k=>v for (k, v) in row if k!="id"); sorted = true)
    bytes2hex(sha256(take!(io)))
end

function multiset(rows)
    d=Dict{String,Int}()
    for row in rows
        key=signature(row)
        d[key]=get(d, key, 0)+1
    end
    d
end

function projection(p, i)
    p["constant"]==0 &&
        p["linear_ids"]==[i] &&
        p["linear_coefficients"]==[1.0] &&
        isempty(p["quadratic_coefficients"])
end

"""逐项证明本次改写只将l≤x≤l换为x=l；检查所有其它行和目标完全相同。"""
function equivalent(original, changed, declared)
    original["variables"]==changed["variables"] || error("Variable identity changed")
    original["objective"]==changed["objective"] || error("Objective changed")
    remove=Set{String}()
    add=Dict{String,Any}[]
    unique_indices=Set{Int}()
    for v in declared
        i=v["index"]
        i in unique_indices && error("Repeated fixed variable")
        push!(unique_indices, i)
        original["variables"][i]==v["name"] && isfinite(v["value"]) || error("Fix identity")
        candidates=filter(original["constraints"]) do r
            length(r["functions"])==1 &&
                projection(only(r["functions"]), i) &&
                r["kind"] in ("lower", "upper")
        end
        length(candidates)==2 && Set(r["kind"] for r in candidates)==Set(["lower", "upper"]) ||
            error("Expected exactly two bounds")
        all(r->r["rhs"]==v["value"], candidates) || error("Bounds are not exactly equal")
        union!(remove, [r["id"] for r in candidates])
        push!(
            add,
            Dict("kind"=>"equal", "rhs"=>v["value"], "functions"=>first(candidates)["functions"]),
        )
    end
    expected=[filter(r->!(r["id"] in remove), original["constraints"]); add]
    multiset(expected)==multiset(changed["constraints"]) ||
        error("Non-equivalent constraint change")
    true
end

function same(left, right)
    keys(left)==keys(right) || error("Replay fields")
    for key in keys(left)
        a, b=left[key], right[key]
        ok=if a isa AbstractFloat && b isa AbstractFloat
            (isnan(a)&&isnan(b)) || isapprox(a, b; rtol = 1e-12, atol = 1e-14)
        else
            a==b
        end
        ok || error("Replay mismatch: $key")
    end
    true
end

"""核对四项原值及精确等价变换；check只读，不加载JuMP/Gurobi，也不重新求解。"""
function check(out; hashes = true)
    if hashes
        manifest=readtoml(joinpath(out, "artifact-hashes.toml"))
        for (path, hash) in manifest["files"]
            (
                isabspath(path)||occursin(':', path)||occursin('\\', path) ||
                any(x->x in ("", ".", ".."), split(path, '/'))
            ) && error("Unsafe path")
            file=joinpath(out, path)
            isfile(file) && !islink(file) && hashfile(file)==hash ||
                error("Changed artifact: $path")
        end
    end
    rules=readtoml(joinpath(out, "rules.toml"))
    summary=readtoml(joinpath(out, "summary.toml"))
    summary["complete"] && length(summary["variants"])==4 || error("Incomplete diagnostic")
    rules["variants"]==[r["id"] for r in summary["variants"]] || error("Variant identity")
    rules["thresholds_unchanged"] && !rules["historical_state_rewritten"] || error("Scope changed")
    rules["probe_sha256"]==hashfile(joinpath(out, "probe.jl")) || error("Probe source")
    rules["input_sha256"]==hashfile(joinpath(out, "input.toml")) || error("Input")
    rules["modes_sha256"]==hashfile(joinpath(out, "fixed-modes.toml")) || error("Modes")
    original=readtoml(joinpath(out, "original-model.toml"))
    table=NamedTuple[]
    for entry in summary["variants"]
        id=entry["id"]
        folder=joinpath(out, id)
        s=readtoml(joinpath(folder, "model.toml"))
        w=readtoml(joinpath(folder, "witness.toml"))
        declared=readtoml(joinpath(folder, "equal-bounds.toml"))["variables"]
        record=readtoml(joinpath(folder, "record.toml"))
        record==entry || error("Summary is not original record")
        if endswith(id, "exact_fix")
            equivalent(original, s, declared)
        else
            s==original || error("Original model changed")
        end
        d=replay(s, w)
        same(d, entry["replay"])
        same(d, readtoml(joinpath(folder, "replay.toml")))
        entry["termination"]==w["termination"] || error("Status changed")
        p=replay(original, Dict("x"=>w["x"], "reported_objective"=>w["reported_objective"]))
        isapprox(p["primal_normalized"], entry["original_primal_normalized"]; rtol = 1e-12) ||
            error("Original primal replay")
        push!(
            table,
            (;
                id,
                termination = w["termination"],
                objective = d["objective_at_primal"],
                primal = d["primal_normalized"],
                stationarity = d["stationarity_normalized"],
                complementarity = d["complementarity_normalized"],
                dual = d["dual_normalized"],
                report_error = d["report_relative_error"],
            ),
        )
    end
    table
end

"""封存已结束的四项诊断，保留原文件字节；已有目标目录一律拒绝覆盖。"""
function archive(source, destination)
    ispath(destination) && error("Preserve existing evidence")
    check(source; hashes = false)
    cp(source, destination)
    cp(@__FILE__, joinpath(destination, "replay.jl"))
    hashes=Dict{String,String}()
    for (dir, _, files) in walkdir(destination), file in files
        full=joinpath(dir, file)
        hashes[replace(relpath(full, destination), '\\'=>'/')]=hashfile(full)
    end
    write_toml(
        joinpath(destination, "artifact-hashes.toml"),
        Dict("schema"=>"r9-bound-diagnostic-evidence-v1", "files"=>hashes),
    )
    check(destination)
end
end

if abspath(PROGRAM_FILE)==@__FILE__
    action=isempty(ARGS) ? "" : ARGS[1]
    output=if action=="check" && length(ARGS)==2
        R9BlockBoundEvidence.check(ARGS[2])
    elseif action=="archive" && length(ARGS)==3
        R9BlockBoundEvidence.archive(ARGS[2], ARGS[3])
    else
        error("Usage: check EVIDENCE | archive SOURCE NEW_EVIDENCE")
    end
    foreach(println, output)
    println(
        "Four-variant numeric replay and exact-bound equivalence passed; no optimization performed.",
    )
end
