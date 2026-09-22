# 只构建/回代原规模模型，不申请优化器或重算调度。
const R9_START_AUDIT_BEGIN=time_ns()/1e9
using TOML, SHA, Dates, JuMP
include("r9_reserve_witness.jl")
const C=R9CommonRun
const S=C.S
length(ARGS)==3 || error("usage: FREEZE VERIFIED_COMMON_RUN NEW_AUDIT")
frozen, run, out=abspath.(ARGS)
ispath(out) && error("Preserve old audit")
mkpath(out)
root=dirname(@__DIR__)
source="src/algorithms/r9_risk_start.jl"
before=S.hashfile(joinpath(root, source))
cp(joinpath(root, source), joinpath(out, "mapping-source.jl"))
cp(@__FILE__, joinpath(out, "audit-source.jl"))
status=Dict{String,Any}(
    "schema"=>"r9-original-start-audit-v1",
    "origin"=>"synthetic",
    "optimization_performed"=>false,
    "started_utc"=>string(now(UTC)),
    "budget_sec"=>600.0,
    "mapping_sha256"=>before,
    "parent_freeze_sha256"=>S.hashfile(joinpath(frozen, "manifest.toml")),
)
try
    state=C.loadfreeze(frozen)
    entries=TOML.parsefile(joinpath(run, "files.toml"))
    for (rel, hash) in entries
        S.hashfile(S.safe(run, rel))==hash || error("Common run changed")
    end
    parent=TOML.parsefile(joinpath(run, "status.toml"))
    parent["status"]=="common_witness_verified" && parent["budget_pass"] ||
        error("No verified common candidate")
    status["parent_witness_sha256"]=entries["witness.toml"]
    status["parent_run_status_sha256"]=entries["status.toml"]
    lib=state.bundle.lib
    Base.include(lib, joinpath(out, "mapping-source.jl"))
    c=C.riskcase(state, "3A")
    w=TOML.parsefile(joinpath(run, "witness.toml"))
    status["case_sha256"]=c.sha256
    tick=time_ns()/1e9
    b=C.call(
        lib,
        :build_r5_risk,
        c;
        pattern = zeros(Int, length(c.data["commitment"]["scenarios"])),
    )
    status["build_sec"]=time_ns()/1e9-tick
    tick=time_ns()/1e9
    vector=C.call(lib, :r9_risk_start_values, c, b, w)
    status["mapping_sec"]=time_ns()/1e9-tick
    tick=time_ns()/1e9
    report=C.call(lib, :audit_r9_risk_start, b, vector)
    status["linear_audit_sec"]=time_ns()/1e9-tick
    status["linear_start_pass"]=report["pass"]
    status["variables"]=report["variables"]
    status["constraints"]=sum(v["count"] for v in values(report["groups"]))
    status["binary_variables"]=count(is_binary, all_variables(b.model))
    status["status"]=report["pass"] ? "original_model_start_checked" :
                     "original_model_start_rejected"
    S.toml(joinpath(out, "linear-audit.toml"), report)
    S.hashfile(joinpath(root, source))==before || error("Mapping changed during audit")
catch err
    status["status"]="execution_error"
    open(io->showerror(io, err, catch_backtrace()), joinpath(out, "failure.txt"), "w")
end
status["elapsed_sec"]=time_ns()/1e9-R9_START_AUDIT_BEGIN
status["budget_pass"]=status["elapsed_sec"]<=600
S.toml(joinpath(out, "status.toml"), status)
S.toml(
    joinpath(out, "files.toml"),
    Dict(rel=>S.hashfile(S.safe(out, rel)) for rel in S.inventory(out)),
)
println(
    status["status"],
    " vars=",
    get(status, "variables", 0),
    " constraints=",
    get(status, "constraints", 0),
    " seconds=",
    status["elapsed_sec"],
)
