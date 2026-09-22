# 事后诊断：固定独立计划是否向DSO索取了超过其额定上界的热量。
# 使用冻结原值和实际变量上界；忽略全部非负管损，让网络条件更有利。
module R9IndependentHeat
using TOML, SHA, CSV, JuMP
include("r9_network_evidence.jl")
const E=R9NetworkEvidence
const S=E.S
q(x) = Rational{BigInt}(Float64(x))
hashfile(p) = bytes2hex(sha256(read(p)))

function calculate(report)
    meta=TOML.parsefile(joinpath(report, "evidence.toml"))
    rows=NamedTuple[]
    proof=Dict{String,Any}[]
    mktempdir() do dir
        E.restore(report, meta["study_files"], dir)
        hashfile(joinpath(dir, "manifest.toml"))==meta["study_manifest_sha256"] ||
            error("Parent changed")
        manifest=S.check(dir)
        lib=S.library(joinpath(dir, "code"))
        for entry in manifest["methods"]
            entry["operation"]=="independent" || continue
            path=joinpath(dir, "runs", entry["id"], "record")
            checked=S.call(lib, :r9_trading_read_current, path)
            c, r=checked.case, checked.result
            checked.validation["local_plans_pass"] ||
                error("Diagnosis requires complete accepted local plans")
            locals=Dict(s["actor"]=>s for s in r["stages"] if s["stage"]=="local")
            # 无优化器，直接取冻结模型的实际热出力变量上界，避免额定功率乘积舍入不一致。
            b=S.call(lib, :build_r9_trading_model, c)
            devices=c.data["devices"]
            for t in 1:c.data["T"]
                demand=sum(q(x[t]) for x in c.data["heat"]["H_background_MW"])
                generation=zero(demand)
                for (i, s) in locals
                    v=s["values"]
                    demand+=q(v["H_D"][i][t])
                    for (j, g) in enumerate(devices)
                        g["owner"]==i || continue
                        demand+=q(v["H_cons"][j][t])
                        generation+=q(v["H_gen"][j][t])
                    end
                end
                upper=zero(demand)
                bounds=Dict{String,Any}[]
                for (j, g) in enumerate(devices)
                    g["owner"]==1 || continue
                    cap=upper_bound(b.variables["H_gen"][j, t])
                    isfinite(cap) || error("Operator bound must be finite")
                    upper+=q(cap)
                    push!(bounds, Dict("device"=>g["id"], "H_upper_MW"=>cap))
                end
                required=demand-generation
                deficit=required-upper
                push!(
                    rows,
                    (
                        method = entry["id"],
                        t = t,
                        required_DSO_heat_without_losses_MW = Float64(required),
                        DSO_heat_upper_MW = Float64(upper),
                        deficit_MW = Float64(deficit),
                        positive_deficit = deficit>0,
                    ),
                )
                if deficit>0
                    push!(
                        proof,
                        Dict(
                            "method"=>entry["id"],
                            "t"=>t,
                            "input_sha256"=>c.sha256,
                            "deficit_numerator"=>string(numerator(deficit)),
                            "deficit_denominator"=>string(denominator(deficit)),
                            "operator_bounds"=>bounds,
                            "loss_assumption"=>"all_nonnegative_losses_omitted",
                            "scope"=>"fixed_saved_independent_plans; not central infeasibility",
                        ),
                    )
                end
            end
        end
    end
    (; rows, proof, study_manifest_sha256 = meta["study_manifest_sha256"])
end

function create(report, out)
    ispath(out) && error("Do not overwrite diagnostic")
    data=calculate(report)
    mkpath(out)
    CSV.write(joinpath(out, "operator-heat.csv"), data.rows; newline = '\n')
    S.toml(
        joinpath(out, "proof.toml"),
        Dict(
            "schema"=>"r9-independent-heat-v1",
            "positive_rows"=>data.proof,
            "selection"=>"post_result_global_heat_balance_diagnostic",
            "solver_used"=>false,
            "study_manifest_sha256"=>data.study_manifest_sha256,
        ),
    )
    cp(@__FILE__, joinpath(out, "audit-source.jl"))
    S.toml(
        joinpath(out, "hashes.toml"),
        Dict("files"=>Dict(f=>hashfile(joinpath(out, f)) for f in readdir(out))),
    )
    println(
        "Independent fixed-plan heat diagnostic: ",
        length(data.rows),
        " rows, ",
        count(x->x.positive_deficit, data.rows),
        " positive contradictions; no optimization.",
    )
end

function check(report, out)
    files=TOML.parsefile(joinpath(out, "hashes.toml"))["files"]
    for (file, h) in files
        hashfile(S.safe(out, file))==h || error("Diagnostic bytes changed")
    end
    data=calculate(report)
    io=IOBuffer()
    CSV.write(io, data.rows; newline = '\n')
    take!(io)==read(joinpath(out, "operator-heat.csv")) || error("Diagnostic table changed")
    p=TOML.parsefile(joinpath(out, "proof.toml"))
    isequal(p["positive_rows"], data.proof) &&
    p["study_manifest_sha256"]==data.study_manifest_sha256 &&
    !p["solver_used"] || error("Diagnostic certificate changed")
    println("Fixed-plan operator bounds and every exact positive deficit rechecked.")
    true
end

if abspath(PROGRAM_FILE)==abspath(@__FILE__)
    length(ARGS)==3 || error("usage: audit_r9_independent_heat.jl create|check SUMMARY AUDIT")
    ARGS[1]=="create" ? create(abspath(ARGS[2]), abspath(ARGS[3])) :
    ARGS[1]=="check" ? check(abspath(ARGS[2]), abspath(ARGS[3])) : error("Unknown action")
end
end
