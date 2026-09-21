# 四方法原值封存、独立重验与字面线性容量证书；不调用优化器。
module R9TradingEvidence
using TOML, SHA, CSV, JuMP
include("r9_trading_study.jl")
include("r9_fixed_evidence.jl")
module Capacity
using TOML, SHA
include("../src/verification/r9_trading_capacity.jl")
end
const ROOT=dirname(@__DIR__)
const S=R9TradingStudy
const O=R9FixedEvidence
q(x) = Rational{BigInt}(Float64(x))
parts(x) = Dict("numerator"=>string(numerator(x)), "denominator"=>string(denominator(x)))

"""从冻结JuMP线性式构造精确加权恒等式及变量界证书，不求解、不依赖IIS锥属性。"""
function literal_witness(lib, c, p)
    b=S.call(lib, :build_r9_trading_model, c)
    d=c.data
    T, n, R=d["T"], d["heat"]["nodes"], length(d["heat"]["pipes"])
    terms=Dict{VariableRef,Rational{BigInt}}()
    rhs=zero(Rational{BigInt})
    rows=Dict{String,Any}[]
    function add(id, i, weight)
        cr=b.constraints[id][i]
        obj=constraint_object(cr)
        obj.func isa AffExpr && obj.set isa MOI.EqualTo || error("Not a linear equality")
        rhs+=weight*(q(obj.set.value)-q(constant(obj.func)))
        for (a, x) in linear_terms(obj.func)
            terms[x]=get(terms, x, zero(rhs))+weight*q(a)
        end
        push!(
            rows,
            Dict("equation"=>id, "ordinal"=>i, "weight"=>parts(weight), "expression"=>string(cr)),
        )
    end
    t=p["t"]
    for i in p["nodes"]
        add("R9-T5-heat-balance", (t-1)*n+i, q(1))
    end
    for i in p["internal_pipes"], side in 1:2
        add("R9-T5-loss", 2*((t-1)*R+i-1)+side, q(-1))
    end
    for device in p["devices"]
        device["admissible_heat_upper_MW"]<device["nameplate_heat_MW"] || continue
        j=device["index"]
        H, P=b.variables["H_gen"][j, t], b.variables["P_cons"][j, t]
        equations=b.constraints["R9-T2-P2H"]
        i=only(
            i for
            i in eachindex(equations) if coefficient(constraint_object(equations[i]).func, H)!=0
        )
        add("R9-T2-P2H", i, -terms[H]/q(coefficient(constraint_object(equations[i]).func, H)))
        equations=b.constraints["ch04-030:031"]
        branch=b.variables["P_branch"][device["electric_edge"], t]
        i=only(
            i for
            i in eachindex(equations) if coefficient(constraint_object(equations[i]).func, P)!=0 &&
                coefficient(constraint_object(equations[i]).func, branch)!=0
        )
        add("ch04-030:031", i, -terms[P]/q(coefficient(constraint_object(equations[i]).func, P)))
    end
    upper=zero(rhs)
    bounds=Dict{String,Any}[]
    for (x, a) in sort(collect(terms); by = z->name(first(z)))
        iszero(a) && continue
        bound=is_fixed(x) ? fix_value(x) : a>0 ? upper_bound(x) : lower_bound(x)
        isfinite(bound) || error("Necessary certificate has an unbounded variable")
        upper+=a*q(bound)
        push!(
            bounds,
            Dict(
                "variable"=>name(x),
                "coefficient"=>parts(a),
                "bound"=>bound,
                "side"=>is_fixed(x) ? "fixed" : a>0 ? "upper" : "lower",
            ),
        )
    end
    deficit=rhs-upper
    expected=parse(BigInt, p["exact_deficit"]["numerator"])//parse(
        BigInt,
        p["exact_deficit"]["denominator"],
    )
    deficit==expected || error("Input derivation differs from literal model coefficient proof")
    Dict(
        "schema"=>"r9-trading-literal-cut-v1",
        "input_sha256"=>c.sha256,
        "rows"=>rows,
        "bounds"=>bounds,
        "exact_deficit"=>parts(deficit),
        "deficit_MW"=>Float64(deficit),
        "positive_deficit"=>deficit>0,
        "solver_used"=>false,
        "frozen_model_built_without_optimizer"=>true,
    )
end

"""使用同一份冻结科学模块逐值重读全部方法，区分局部计划与网络调度。"""
function replay(study)
    meta=S.check_inputs(study)
    lib=S.library(joinpath(study, "code"))
    c=S.call(lib, :load_r9_trading_case, joinpath(study, "input.toml"))
    summaries, stages=NamedTuple[], NamedTuple[]
    for entry in meta["protocol"]["methods"]
        id=entry["id"]
        folder=joinpath(study, "runs", id)
        receipt=TOML.parsefile(joinpath(folder, "receipt.toml"))
        receipt["entry"]==entry && receipt["input_sha256"]==c.sha256 || error("Method identity")
        receipt["manifest_sha256"]==S.hashfile(joinpath(study, "manifest.toml")) ||
            error("Parent identity")
        receipt["solver_options"]==meta["protocol"]["gurobi"] || error("Solver rules changed")
        receipt["raw_result_sha256"]==S.hashfile(joinpath(folder, "raw-result.toml")) ||
            error("Raw hash")
        receipt["record_manifest_sha256"]==S.hashfile(joinpath(folder, "record", "hashes.toml")) ||
            error("Record hash")
        raw=TOML.parsefile(joinpath(folder, "raw-result.toml"))
        raw["source_hashes_at_solve"]==S.call(lib, :r9_trading_science_hashes) ||
            error("Science source mismatch")
        checked=S.call(lib, :r9_trading_read_current, joinpath(folder, "record"))
        r=checked.result
        receipt["status"]==raw["status"]==r["status"] || error("Status mismatch")
        isequal(receipt["run_validation"], checked.validation) ||
            error("Receipt validation differs")
        transformed=deepcopy(raw)
        transformed["run_id"]="record"
        for (i, stage) in enumerate(transformed["stages"])
            stage["validation"]=S.call(lib, :r9_trading_summary, stage["validation"])
            stage["residual_file"]="residuals/stage-"*lpad(string(i), 2, '0')*".csv"
        end
        isequal(transformed, r) || error("Raw values differ from saved stages")
        push!(
            summaries,
            (
                method = id,
                operation = entry["operation"],
                electric = entry["electric"],
                status = r["status"],
                model_pass = checked.validation["model_pass"],
                electric_original_pass = checked.validation["electric_original_pass"],
                local_plans_pass = checked.validation["local_plans_pass"],
                heat_pass = checked.validation["heat_energy_mass_pass"],
                ledger_pass = checked.validation["ledger_pass"],
                system_cost_CNY = get(r, "system_cost_CNY", NaN),
                method_elapsed_sec = receipt["method_elapsed_sec"],
                process_elapsed_sec = receipt["process_elapsed_with_archive_sec"],
                method_budget_pass = receipt["method_budget_pass"],
                process_budget_pass = receipt["process_budget_pass"],
            ),
        )
        for (i, s) in enumerate(r["stages"])
            push!(
                stages,
                (
                    method = id,
                    stage_index = i,
                    stage = s["stage"],
                    actor = get(s, "actor", 0),
                    termination = s["termination"],
                    model_pass = s["validation"]["model_pass"],
                    objective_kind = s["objective_kind"],
                    objective = get(s, "solver_objective", NaN),
                ),
            )
        end
    end
    A=setdiff(1:c.data["heat"]["nodes"], [5, 6, 23])
    cut=Capacity.r9_trading_heat_cut(c, A, 8)
    literal=literal_witness(lib, c, cut)
    capacity=Capacity.audit_r9_trading_capacity(c)
    cuts=[Capacity.r9_trading_heat_cut(c, A, t) for t in 1:c.data["T"]]
    table=[
        (
            t = x["t"],
            minimum_demand_MW = x["minimum_demand_MW"],
            internal_loss_MW = x["internal_loss_MW"],
            maximum_supply_MW = x["maximum_supply_MW"],
            maximum_import_MW = x["maximum_import_MW"],
            deficit_MW = x["deficit_MW"],
            positive_deficit = x["positive_deficit"],
        ) for x in cuts
    ]
    (; summaries, stages, cut, literal, capacity, table)
end

function restore(out, files, target)
    for (rel, hash) in files
        path=S.safe(target, rel)
        mkpath(dirname(path))
        write(path, O.bytes(out, hash))
    end
end

"""封存四项负结果与原始局部计划，长文件无损分片，保留两次诊断。"""
function archive(study, out, diagnostics)
    ispath(out) && error("Do not overwrite evidence")
    data=replay(study)
    mkpath(joinpath(out, "objects"))
    meta=Dict{String,Any}(
        "schema"=>"r9-trading-evidence-v1",
        "origin"=>"synthetic",
        "input_sha256"=>data.cut["input_sha256"],
        "study_manifest_sha256"=>S.hashfile(joinpath(study, "manifest.toml")),
        "study_files"=>O.pack(out, study),
        "diagnostics"=>Dict{String,Any}(),
        "no_accepted_network_schedule"=>!any(x.model_pass for x in data.summaries),
        "diagnostic_subset_selection"=>"post_result_IIS_heat_nodes_except_5_6_23",
        "bargaining"=>false,
        "distributed_algorithm"=>false,
        "solver_used_for_replay"=>false,
    )
    for path in diagnostics
        meta["diagnostics"][basename(path)]=O.pack(out, path)
    end
    for (name, x) in
        (("summary", data.summaries), ("stages", data.stages), ("heat-cut", data.table))
        CSV.write(joinpath(out, name*".csv"), x; newline = '\n')
    end
    for (name, x) in
        (("capacity", data.capacity), ("heat-cut-proof", data.cut), ("literal-proof", data.literal))
        S.toml(joinpath(out, name*".toml"), x)
    end
    mkpath(joinpath(out, "code", "scripts"))
    mkpath(joinpath(out, "code", "src", "verification"))
    for file in (
        "scripts/r9_trading_evidence.jl",
        "scripts/r9_trading_study.jl",
        "scripts/r9_fixed_evidence.jl",
        "src/verification/r9_trading_capacity.jl",
    )
        cp(joinpath(ROOT, file), joinpath(out, "code", file))
    end
    meta["derived_files"]=Dict(
        rel=>S.hashfile(joinpath(out, rel)) for rel in (
            "summary.csv",
            "stages.csv",
            "heat-cut.csv",
            "capacity.toml",
            "heat-cut-proof.toml",
            "literal-proof.toml",
            "code/scripts/r9_trading_evidence.jl",
            "code/scripts/r9_trading_study.jl",
            "code/scripts/r9_fixed_evidence.jl",
            "code/src/verification/r9_trading_capacity.jl",
        )
    )
    S.toml(joinpath(out, "evidence.toml"), meta)
    println(
        "Archived four frozen methods; positive literal deficit MW=",
        data.literal["deficit_MW"],
    )
end

"""无许可、无求解器重验：哈希、原值、模型残差、比较表及精确容量证书。"""
function check(out)
    meta=TOML.parsefile(joinpath(out, "evidence.toml"))
    meta["schema"]=="r9-trading-evidence-v1" && meta["origin"]=="synthetic" ||
        error("Evidence identity")
    for (rel, hash) in meta["derived_files"]
        S.hashfile(S.safe(out, rel))==hash || error("Derived file changed")
    end
    for files in values(meta["diagnostics"]), (_, hash) in files
        O.bytes(out, hash)
    end
    mktempdir() do dir
        study=joinpath(dir, "study")
        restore(out, meta["study_files"], study)
        S.hashfile(joinpath(study, "manifest.toml"))==meta["study_manifest_sha256"] ||
            error("Study manifest changed")
        data=replay(study)
        data.cut["input_sha256"]==meta["input_sha256"] || error("Input changed")
        for (name, x) in
            (("summary", data.summaries), ("stages", data.stages), ("heat-cut", data.table))
            io=IOBuffer()
            CSV.write(io, x; newline = '\n')
            take!(io)==read(joinpath(out, name*".csv")) || error("Table differs: "*name)
        end
        for (name, x) in (
            ("capacity", data.capacity),
            ("heat-cut-proof", data.cut),
            ("literal-proof", data.literal),
        )
            isequal(TOML.parsefile(joinpath(out, name*".toml")), x) || error("Proof differs: "*name)
        end
        println(
            "Frozen replay passed: ",
            length(data.summaries),
            " methods, ",
            length(data.stages),
            " stages; literal deficit=",
            data.literal["deficit_MW"],
            " MW",
        )
    end
    true
end

if abspath(PROGRAM_FILE)==@__FILE__
    if length(ARGS)>=3 && ARGS[1]=="archive"
        archive(abspath(ARGS[2]), abspath(ARGS[3]), abspath.(ARGS[4:end]))
    elseif length(ARGS)==2 && ARGS[1]=="check"
        check(abspath(ARGS[2]))
    else
        error(
            "usage: r9_trading_evidence.jl archive STUDY NEW_SUMMARY [DIAGNOSTICS...] | check SUMMARY",
        )
    end
end
end
