# 完整预算从导入前开始；冻结数据不重抽、历史负结果不重写。
const R9_COMMON_PROCESS_START=time_ns()/1e9
module R9CommonRun
using TOML, SHA, Dates, JuMP, Clarabel
include("r9_reserve_study.jl")
const S=R9ReserveStudy
const ROOT=normpath(joinpath(@__DIR__, ".."))
const EXTRA=["src/formulations/r9_common_witness.jl", "src/algorithms/r9_common_witness.jl"]
clock() = time_ns()/1e9
call(lib, name, args...; kwargs...) = Base.invokelatest() do
    getfield(lib, name)(args...; kwargs...)
end

function freeze(study, out)
    ispath(out) && error("Preserve previous freeze")
    S.check(study)
    mkpath(out)
    cp(study, joinpath(out, "study"))
    sources=vcat(EXTRA, ["scripts/r9_reserve_witness.jl", "scripts/r9_reserve_study.jl"])
    hashes=Dict(rel=>S.hashfile(S.safe(ROOT, rel)) for rel in sources)
    for rel in sources
        target=S.safe(out, "implementation/"*rel)
        mkpath(dirname(target))
        cp(S.safe(ROOT, rel), target)
    end
    all(S.hashfile(S.safe(ROOT, k))==h for (k, h) in hashes) || error("Source changed at freeze")
    m=Dict(
        "schema"=>"r9-common-freeze-v1",
        "origin"=>"synthetic",
        "source_hashes"=>hashes,
        "optimization_performed"=>false,
        "parent_study_sha256"=>S.hashfile(joinpath(study, "manifest.toml")),
        "created_utc"=>string(now(UTC)),
        "git_commit"=>readchomp(`git -C $ROOT rev-parse HEAD`),
        "complete_budget_sec"=>600.0,
        "restricted_solve_max_sec"=>180.0,
        "files"=>Dict(rel=>S.hashfile(S.safe(out, rel)) for rel in S.inventory(out)),
    )
    S.toml(joinpath(out, "manifest.toml"), m)
    write(joinpath(out, "manifest.sha256"), S.hashfile(joinpath(out, "manifest.toml"))*"\n")
    println("Common witness sources frozen; original 100 scenarios retained; no optimization.")
end

function loadfreeze(out)
    S.hashfile(joinpath(out, "manifest.toml"))==strip(
        read(joinpath(out, "manifest.sha256"), String),
    ) || error("Manifest changed")
    m=TOML.parsefile(joinpath(out, "manifest.toml"))
    m["schema"]=="r9-common-freeze-v1" && !m["optimization_performed"] || error("Wrong freeze")
    Set(S.inventory(out))==union(
        Set(keys(m["files"])),
        Set(["manifest.toml", "manifest.sha256"]),
    ) || error("Frozen inventory changed")
    for (rel, h) in m["files"]
        S.hashfile(S.safe(out, rel))==h || error("Frozen bytes changed: $rel")
    end
    bundle=S.check(joinpath(out, "study"))
    S.hashfile(joinpath(out, "study/manifest.toml"))==m["parent_study_sha256"] ||
        error("Parent identity")
    for rel in EXTRA
        Base.include(bundle.lib, S.safe(out, "implementation/"*rel))
    end
    (; bundle, m)
end

function riskcase(state, scheme)
    b=state.bundle
    c=call(
        b.lib,
        :r9_reserve_risk_case,
        b.template,
        b.dataset.sets["train"],
        b.dataset.representatives,
        b.spec,
        scheme,
    )
    entry=only(e for e in b.manifest["methods"] if e["scheme"]==scheme && !e["pilot"])
    c.sha256==entry["case_sha256"] || error("Original risk input changed")
    c
end

function summary(lib, c, w)
    r=call(lib, :r9_common_risk_candidate, c, w)
    v=call(lib, :validate_r5_risk, c, r)
    groups=Dict{String,Any}()
    function add(row, scope)
        key=scope*"/"*row["group"]*"/"*get(row, "unit", "1")
        g=get!(groups, key, Dict{String,Any}("count"=>0, "failed"=>0, "max_normalized"=>0.0))
        g["count"]+=1
        g["failed"]+=!row["pass"]
        g["max_normalized"]=max(g["max_normalized"], row["normalized"])
    end
    for row in v["rows"]
        add(row, "risk")
    end
    scenario=Dict{String,Any}()
    for id in sort!(collect(keys(v["scenarios"])))
        sv=v["scenarios"][id]
        vv=sv["validation"]
        for row in vv["rows"]
            add(row, "physical")
        end
        scenario[id]=Dict(
            "model_pass"=>vv["model_pass"],
            "rows"=>length(vv["rows"]),
            "recourse_cost"=>sv["recourse_cost"],
            "comfort_excess_K"=>sv["comfort_excess_K"],
            "max_normalized"=>maximum(x["normalized"] for x in vv["rows"]),
        )
    end
    d=Dict{String,Any}(
        "case_sha256"=>c.sha256,
        "groups"=>groups,
        "scenarios"=>scenario,
        "scenarios_checked"=>length(scenario),
        "run_id"=>r["run_id"],
        "original_risk_optimality_claim"=>false,
        "restriction_residual_MW"=>w["restriction_residual_MW"],
    )
    for k in (
        "status",
        "model_pass",
        "risk_pass",
        "cost_pass",
        "optimality_pass",
        "valid_bound",
        "day_ahead_cost",
        "nominal_net_cost",
        "worst_net_cost",
        "worst_violation_probability",
        "selected_violation_bound",
    )
        haskey(v, k) && (d[k]=v[k])
    end
    d
end

function run(frozen, out; started = clock(), witness_source = nothing)
    ispath(out) && error("Preserve old run")
    mkpath(out)
    status=Dict{String,Any}(
        "schema"=>"r9-common-run-v1",
        "status"=>"started",
        "freeze_sha256"=>S.hashfile(joinpath(frozen, "manifest.toml")),
        "complete_budget_sec"=>600.0,
        "created_utc"=>string(now(UTC)),
    )
    S.toml(joinpath(out, "status.toml"), status)
    try
        state=loadfreeze(frozen)
        self="implementation/scripts/r9_reserve_witness.jl"
        S.hashfile(@__FILE__)==state.m["files"][self] || error("Run frozen implementation")
        lib=state.bundle.lib
        c=riskcase(state, "3A")
        status["preparation_sec"]=clock()-started
        opt=optimizer_with_attributes(
            Clarabel.Optimizer,
            "tol_feas"=>1e-9,
            "tol_gap_abs"=>1e-9,
            "tol_gap_rel"=>1e-9,
        )
        budget=min(state.m["restricted_solve_max_sec"], 600.0-(clock()-started)-180.0)
        budget>0 || error("Budget exhausted before restricted solve")
        if witness_source===nothing
            w=call(lib, :solve_r9_common_witness, c; optimizer = opt, budget_sec = budget)
            status["new_optimization_performed"]=true
        else
            files=TOML.parsefile(joinpath(witness_source, "files.toml"))
            S.hashfile(joinpath(witness_source, "witness.toml"))==files["witness.toml"] ||
                error("Parent witness changed")
            w=TOML.parsefile(joinpath(witness_source, "witness.toml"))
            w["case_sha256"]==c.sha256 || error("Parent original input differs")
            status["new_optimization_performed"]=false
            status["parent_witness_sha256"]=files["witness.toml"]
            status["parent_run_id"]=w["run_id"]
        end
        S.toml(joinpath(out, "witness.toml"), w)
        witness_source===nothing ||
            S.hashfile(joinpath(out, "witness.toml"))==status["parent_witness_sha256"] ||
            error("Replayed witness bytes differ")
        println(
            "Restricted solve: ",
            w["status"],
            " candidate=",
            w["has_candidate"],
            " elapsed=",
            clock()-started,
        )
        flush(stdout)
        status["restricted_status"]=w["status"]
        status["has_common_candidate"]=w["has_candidate"]
        status["schemes"]=Dict{String,Any}()
        if w["has_candidate"]
            for scheme in ("3A", "3B", "3C")
                clock()-started<570.0 || error("Budget exhausted before all scenario checks")
                case=scheme=="3A" ? c : riskcase(state, scheme)
                tick=clock()
                report=summary(lib, case, w)
                S.toml(joinpath(out, "validation-"*scheme*".toml"), report)
                status["schemes"][scheme]=Dict(
                    "model_pass"=>report["model_pass"],
                    "risk_pass"=>report["risk_pass"],
                    "cost_pass"=>report["cost_pass"],
                    "case_sha256"=>case.sha256,
                    "check_sec"=>clock()-tick,
                )
                println(
                    scheme,
                    " model=",
                    report["model_pass"],
                    " risk=",
                    report["risk_pass"],
                    " cost=",
                    report["cost_pass"],
                    " elapsed=",
                    clock()-started,
                )
                flush(stdout)
            end
            status["status"]=all(
                all(v[k] for k in ("model_pass", "risk_pass", "cost_pass")) for
                v in values(status["schemes"])
            ) ? "common_witness_verified" : "common_witness_rejected"
        else
            status["status"]="no_common_witness_not_original_infeasibility_proof"
        end
    catch err
        status["status"]="execution_error"
        open(io->showerror(io, err, catch_backtrace()), joinpath(out, "failure.txt"), "w")
    end
    status["elapsed_sec"]=clock()-started
    status["budget_pass"]=status["elapsed_sec"]<=600.0
    S.toml(joinpath(out, "status.toml"), status)
    files=Dict(rel=>S.hashfile(S.safe(out, rel)) for rel in S.inventory(out))
    S.toml(joinpath(out, "files.toml"), files)
    println(status["status"], " complete seconds=", status["elapsed_sec"])
end

function check(frozen, out)
    state=loadfreeze(frozen)
    files=TOML.parsefile(joinpath(out, "files.toml"))
    Set(S.inventory(out))==union(Set(keys(files)), Set(["files.toml"])) ||
        error("Run inventory changed")
    for (rel, h) in files
        S.hashfile(S.safe(out, rel))==h || error("Run bytes changed: $rel")
    end
    status=TOML.parsefile(joinpath(out, "status.toml"))
    status["freeze_sha256"]==S.hashfile(joinpath(frozen, "manifest.toml")) ||
        error("Freeze identity changed")
    w=TOML.parsefile(joinpath(out, "witness.toml"))
    if w["has_candidate"]
        for scheme in sort!(collect(keys(status["schemes"])))
            c=riskcase(state, scheme)
            actual=summary(state.bundle.lib, c, w)
            expected=TOML.parsefile(joinpath(out, "validation-"*scheme*".toml"))
            isequal(actual, expected) || error("Independent replay mismatch: $scheme")
        end
    end
    println("Frozen common witness rechecked; no optimization; ", status["status"])
    status
end

function main(args; started = clock())
    if length(args)==4 && args[1]=="replay"
        return run(abspath(args[2]), abspath(args[4]); started, witness_source = abspath(args[3]))
    end
    length(args)==3 ||
        error("usage: freeze STUDY NEW_FREEZE | run FREEZE NEW_RUN | check FREEZE RUN")
    action, a, b=args
    action=="freeze" ? freeze(abspath(a), abspath(b)) :
    action=="run" ? run(abspath(a), abspath(b); started) :
    action=="check" ? check(abspath(a), abspath(b)) : error("Unknown action")
end
end
if abspath(PROGRAM_FILE)==@__FILE__
    R9CommonRun.main(ARGS; started = R9_COMMON_PROCESS_START)
end
