const R9_SEEDED_PROCESS_START=time_ns()/1e9
module R9SeededStudy
using TOML, SHA, Dates, JuMP, HiGHS
include("r9_reserve_witness.jl")
const C=R9CommonRun
const S=C.S
const ROOT=normpath(joinpath(@__DIR__, ".."))
const SOURCES=[
    "src/algorithms/r9_risk_start.jl",
    "src/algorithms/r9_seeded_risk.jl",
    "scripts/r9_seeded_study.jl",
    "scripts/r9_gurobi_start.jl",
    "scripts/run_r9_seeded_batch.jl",
    "scripts/r9_reserve_witness.jl",
    "scripts/r9_reserve_study.jl",
    "configs/r9/seeded-study.toml",
]
clock() = time_ns()/1e9

"""冻结新求解协议、初值及实现；原输入包作为带哈希的显式只读依赖，不复制或改写。"""
function freeze(common, evidence, out)
    ispath(out) && error("Preserve old freeze")
    state=C.loadfreeze(common)
    protocol=TOML.parsefile(joinpath(ROOT, "configs/r9/seeded-study.toml"))
    protocol["parent_common_sha256"]==S.hashfile(joinpath(common, "manifest.toml")) ||
        error("Common identity")
    protocol["parent_study_sha256"]==state.m["parent_study_sha256"] || error("Study identity")
    w=joinpath(evidence, "run/witness.toml")
    protocol["parent_witness_sha256"]==S.hashfile(w) || error("Witness identity")
    parent=TOML.parsefile(joinpath(evidence, "run/status.toml"))
    parent["status"]=="common_witness_verified" && parent["budget_pass"] ||
        error("Unverified witness")
    mkpath(out)
    before=Dict(p=>S.hashfile(S.safe(ROOT, p)) for p in SOURCES)
    for p in SOURCES
        target=S.safe(out, "implementation/"*p)
        mkpath(dirname(target))
        cp(S.safe(ROOT, p), target)
    end
    cp(w, joinpath(out, "witness.toml"))
    cp(joinpath(evidence, "run/status.toml"), joinpath(out, "parent-status.toml"))
    all(
        S.hashfile(S.safe(ROOT, p))==h==S.hashfile(S.safe(out, "implementation/"*p)) for
        (p, h) in before
    ) || error("Concurrent change")
    m=Dict(
        "schema"=>"r9-seeded-freeze-v1",
        "origin"=>"synthetic",
        "optimization_performed"=>false,
        "created_utc"=>string(now(UTC)),
        "git_commit"=>readchomp(`git -C $ROOT rev-parse HEAD`),
        "git_status"=>read(`git -C $ROOT status --porcelain=v1`, String),
        "protocol"=>protocol,
        "source_hashes"=>before,
        "cases"=>Dict(
            e["scheme"]=>e["case_sha256"] for e in state.bundle.manifest["methods"] if !e["pilot"]
        ),
        "files"=>Dict(p=>S.hashfile(S.safe(out, p)) for p in S.inventory(out)),
    )
    S.toml(joinpath(out, "manifest.toml"), m)
    write(joinpath(out, "manifest.sha256"), S.hashfile(joinpath(out, "manifest.toml"))*"\n")
    println(
        "Frozen three original 100-scenario cases, explicit seed and solver protocol; no optimization.",
    )
end

function loadfreeze(common, frozen)
    S.hashfile(joinpath(frozen, "manifest.toml"))==strip(
        read(joinpath(frozen, "manifest.sha256"), String),
    ) || error("Manifest changed")
    m=TOML.parsefile(joinpath(frozen, "manifest.toml"))
    m["schema"]=="r9-seeded-freeze-v1" && !m["optimization_performed"] || error("Freeze scope")
    Set(S.inventory(frozen))==union(
        Set(keys(m["files"])),
        Set(["manifest.toml", "manifest.sha256"]),
    ) || error("Freeze inventory")
    for (p, h) in m["files"]
        S.hashfile(S.safe(frozen, p))==h || error("Changed freeze: $p")
    end
    p=TOML.parsefile(joinpath(frozen, "implementation/configs/r9/seeded-study.toml"))
    isequal(p, m["protocol"]) || error("Protocol mismatch")
    p["budget_sec"]==600.0 &&
    p["optimization_cutoff_fraction"]==0.7 &&
    p["oracle_cutoff_fraction"]==0.8 || error("Budget protocol")
    p["parent_common_sha256"]==S.hashfile(joinpath(common, "manifest.toml")) ||
        error("Wrong common input")
    p["parent_witness_sha256"]==S.hashfile(joinpath(frozen, "witness.toml")) ||
        error("Wrong witness")
    state=C.loadfreeze(common)
    state.m["parent_study_sha256"]==p["parent_study_sha256"] || error("Wrong original input")
    for file in ("r9_risk_start.jl", "r9_seeded_risk.jl")
        Base.include(state.bundle.lib, joinpath(frozen, "implementation/src/algorithms", file))
    end
    (;
        state,
        manifest = m,
        protocol = p,
        witness = TOML.parsefile(joinpath(frozen, "witness.toml")),
    )
end

"""保存全部数值和按组、按情景检查摘要；完整原残差可从这些原值重新生成。"""
function compact_validation(v)
    out=Dict{String,Any}(k=>val for (k, val) in v if k ∉ ("rows", "scenarios"))
    groups=Dict{String,Any}()
    function add(row, scope)
        key=scope*"/"*row["group"]*"/"*get(row, "unit", "1")
        g=get!(groups, key, Dict{String,Any}("count"=>0, "failed"=>0, "max_normalized"=>0.0))
        g["count"]+=1
        g["failed"]+=!row["pass"]
        g["max_normalized"]=max(g["max_normalized"], row["normalized"])
    end
    for row in get(v, "rows", [])
        add(row, "risk")
    end
    scenarios=Dict{String,Any}()
    for (id, s) in get(v, "scenarios", Dict())
        sv=s["validation"]
        scenarios[id]=Dict{String,Any}(k=>val for (k, val) in s if k!="validation")
        scenarios[id]["validation"]=Dict(k=>val for (k, val) in sv if k!="rows")
        scenarios[id]["rows"]=length(sv["rows"])
        scenarios[id]["max_normalized"]=maximum(
            (row["normalized"] for row in sv["rows"]);
            init = 0.0,
        )
        for row in sv["rows"]
            add(row, "physical")
        end
    end
    out["groups"]=groups
    out["scenarios"]=scenarios
    out
end

function save_numeric(out, r)
    ispath(out) && error("Preserve numeric run")
    mkpath(out)
    meta=Dict{String,Any}(k=>v for (k, v) in r if k ∉ ("scenarios", "validation"))
    members=Dict{String,String}()
    for (i, id) in enumerate(sort(collect(keys(get(r, "scenarios", Dict())))))
        path="scenario-"*lpad(i, 3, '0')*".toml"
        S.toml(joinpath(out, path), r["scenarios"][id])
        members[id]=path
    end
    S.toml(joinpath(out, "result.toml"), meta)
    S.toml(joinpath(out, "validation.toml"), compact_validation(r["validation"]))
    m=Dict(
        "schema"=>"r9-seeded-numeric-v1",
        "scenarios"=>members,
        "files"=>Dict(p=>S.hashfile(S.safe(out, p)) for p in S.inventory(out)),
    )
    S.toml(joinpath(out, "files.toml"), m)
end

function read_numeric(out)
    m=TOML.parsefile(joinpath(out, "files.toml"))
    m["schema"]=="r9-seeded-numeric-v1" || error("Numeric schema")
    Set(S.inventory(out))==union(Set(keys(m["files"])), Set(["files.toml"])) ||
        error("Numeric inventory")
    for (p, h) in m["files"]
        S.hashfile(S.safe(out, p))==h || error("Numeric bytes changed")
    end
    r=TOML.parsefile(joinpath(out, "result.toml"))
    if !isempty(m["scenarios"])
        r["scenarios"]=Dict(id=>TOML.parsefile(S.safe(out, p)) for (id, p) in m["scenarios"])
    end
    (; result = r, validation = TOML.parsefile(joinpath(out, "validation.toml")))
end

function factory(p, lp, logfile)
    G=getfield(getfield(@__MODULE__, :R9GurobiStart), :Gurobi)
    env=G.Env(Dict{String,Any}("OutputFlag"=>0))
    options=Pair{String,Any}[
        "Threads"=>p["threads"],
        "Seed"=>p["seed"],
        "FeasibilityTol"=>p["feasibility_tolerance"],
        "OptimalityTol"=>p["optimality_tolerance"],
        "IntFeasTol"=>p["integer_tolerance"],
        "MIPGap"=>p["mip_gap"],
        "DualReductions"=>p["dual_reductions"],
        "LogFile"=>logfile,
        "OutputFlag"=>1,
        "LogToConsole"=>0,
    ]
    lp && append!(options, ["Method"=>p["LP_Method"], "LPWarmStart"=>p["LPWarmStart"]])
    optimizer_with_attributes(()->G.Optimizer(env), options...)
end

function run(common, frozen, scheme, out; started = clock())
    ispath(out) && error("Preserve previous run")
    mkpath(out)
    status=Dict{String,Any}(
        "schema"=>"r9-seeded-status-v1",
        "origin"=>"synthetic",
        "scheme"=>scheme,
        "status"=>"started",
        "budget_sec"=>600.0,
        "created_utc"=>string(now(UTC)),
        "freeze_sha256"=>S.hashfile(joinpath(frozen, "manifest.toml")),
    )
    S.toml(joinpath(out, "status.toml"), status)
    try
        bundle=loadfreeze(common, frozen)
        scheme in bundle.protocol["schemes"] || error("Undeclared scheme")
        S.hashfile(@__FILE__)==bundle.manifest["files"]["implementation/scripts/r9_seeded_study.jl"] ||
            error("Use frozen runner")
        c=C.riskcase(bundle.state, scheme)
        c.sha256==bundle.manifest["cases"][scheme] || error("Case changed")
        status["case_sha256"]=c.sha256
        status["parent_witness_sha256"]=bundle.protocol["parent_witness_sha256"]
        path=joinpath(common, "study/code/tools/solvers")
        path in LOAD_PATH || push!(LOAD_PATH, path)
        depot=joinpath(pwd(), ".julia")
        isdir(depot) && !(depot in DEPOT_PATH) && pushfirst!(DEPOT_PATH, depot)
        Base.include(@__MODULE__, joinpath(frozen, "implementation/scripts/r9_gurobi_start.jl"))
        lp=scheme=="3A"
        opt=Base.invokelatest(factory, bundle.protocol, lp, joinpath(out, "solver.log"))
        oracle=optimizer_with_attributes(
            HiGHS.Optimizer,
            "threads"=>1,
            "primal_feasibility_tolerance"=>1e-9,
            "dual_feasibility_tolerance"=>1e-9,
        )
        seed=(m, x; lp)->Base.invokelatest() do
            getfield(getfield(@__MODULE__, :R9GurobiStart), :set_native_start!)(m, x; lp)
        end
        status["preparation_sec"]=clock()-started
        status["status"]="solving"
        S.toml(joinpath(out, "status.toml"), status)
        r=C.call(
            bundle.state.bundle.lib,
            :solve_r9_seeded_risk,
            c,
            bundle.witness;
            optimizer = opt,
            seed! = seed,
            oracle_optimizer = oracle,
            pattern = lp ? zeros(Int, length(c.data["commitment"]["scenarios"])) : nothing,
            budget_sec = 600.0,
            process_start = time()-(clock()-started),
        )
        status["status"]=r["status"]
        status["has_candidate"]=r["has_candidate"]
        status["cost_optimization_complete"]=r["cost_optimization_complete"]
        for k in (
            "model_pass",
            "risk_pass",
            "cost_pass",
            "optimality_pass",
            "valid_bound",
            "worst_net_cost",
            "relative_gap",
            "worst_violation_probability",
        )
            haskey(r["validation"], k) && (status[k]=r["validation"][k])
        end
        tick=clock()
        save_numeric(joinpath(out, "run"), r)
        numeric=read_numeric(joinpath(out, "run"))
        isequal(numeric.validation, compact_validation(r["validation"])) ||
            error("Saved validation mismatch")
        status["save_and_read_sec"]=clock()-tick
        status["numerical_replay_during_save"]=false
    catch err
        status["status"]=occursin(
            r"(?i)license|licence|expired|not licensed",
            sprint(showerror, err),
        ) ? "license_unavailable" : "execution_error"
        open(io->showerror(io, err, catch_backtrace()), joinpath(out, "failure.txt"), "w")
    end
    status["elapsed_sec"]=clock()-started
    status["budget_pass"]=status["elapsed_sec"]<=600.0
    S.toml(joinpath(out, "status.toml"), status)
    println(
        scheme,
        " ",
        status["status"],
        " candidate=",
        get(status, "has_candidate", false),
        " model=",
        get(status, "model_pass", false),
        " seconds=",
        status["elapsed_sec"],
    )
end

"""在原冻结验证器中重算保存的实际候选；只读、无优化、无商业许可。"""
function check(common, frozen, scheme, out)
    bundle=loadfreeze(common, frozen)
    c=C.riskcase(bundle.state, scheme)
    raw=read_numeric(joinpath(out, "run"))
    v=C.call(bundle.state.bundle.lib, :validate_r5_risk, c, raw.result)
    isequal(compact_validation(v), raw.validation) || error("Numerical replay differs")
    status=TOML.parsefile(joinpath(out, "status.toml"))
    status["freeze_sha256"]==S.hashfile(joinpath(frozen, "manifest.toml")) ||
        error("Run parent changed")
    status["scheme"]==scheme && status["case_sha256"]==c.sha256 || error("Run case changed")
    status["status"]==raw.result["status"] || error("Solver status changed")
    for k in ("model_pass", "risk_pass", "cost_pass", "optimality_pass")
        status[k]==v[k] || error("False validation status")
    end
    println("Saved original-model candidate independently replayed: ", scheme)
    v
end

function main(args; started = clock())
    if length(args)==4 && args[1]=="freeze"
        freeze(abspath.(args[2:4])...)
    elseif length(args)==5 && args[1] in ("run", "check")
        a, b, id, out=abspath(args[2]), abspath(args[3]), args[4], abspath(args[5])
        args[1]=="run" ? run(a, b, id, out; started) : check(a, b, id, out)
    else
        error(
            "usage: freeze COMMON_INPUT COMMON_EVIDENCE NEW_FREEZE | run/check COMMON_INPUT FREEZE 3A/3B/3C OUTPUT",
        )
    end
end
end
if abspath(PROGRAM_FILE)==@__FILE__
    R9SeededStudy.main(ARGS; started = R9_SEEDED_PROCESS_START)
end
