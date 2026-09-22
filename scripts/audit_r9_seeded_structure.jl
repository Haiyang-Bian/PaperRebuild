# 从冻结系数表数结构，不构建百万变量模型、不申请优化器。
using TOML, SHA, Dates
include("r9_reserve_witness.jl")
const C=R9CommonRun
const S=C.S
length(ARGS)==3 || error("usage: COMMON_INPUT ORIGINAL_3A_RUN NEW_AUDIT")
common, run, out=abspath.(ARGS)
ispath(out) && error("Preserve old structural audit")
state=C.loadfreeze(common)
lib=state.bundle.lib
c=C.riskcase(state, "3A")
r=TOML.parsefile(joinpath(run, "run/result.toml"))
r["case_sha256"]==c.sha256 || error("Wrong original run")
physical=C.call(lib, :r5_risk_physical_case, c)
entries=Dict{String,Any}()
for sc in physical.data["scenarios"]
    view=C.call(lib, :R5DispatchCase, sc["case"])
    sys=C.call(lib, :r5_dispatch_dual_system, view)
    rows=collect(values(sys.rows))
    entries[sc["id"]]=Dict(
        "variables"=>length(sys.cost),
        "rows"=>length(rows),
        "declared_bound_rows"=>count(q->q.bound, rows),
        "equalities"=>count(q->q.sense==:eq, rows),
        "nonzero_coefficients"=>sum(count(!iszero, values(q.coefficients)) for q in rows),
        "stored_zero_coefficients"=>sum(count(iszero, values(q.coefficients)) for q in rows),
        "nonzero_cost_terms"=>count(!iszero, values(sys.cost)),
    )
end
n=length(entries)
first_rows=length(C.call(lib, :r5_commitment_first_rows, physical))
comfort=2sum(
    length(s["case"]["buildings"])*s["case"]["T"] for s in c.data["commitment"]["scenarios"]
)
variables=3first(c.data["commitment"]["scenarios"])["case"]["T"]+sum(
    e["variables"] for e in values(entries)
)+2(n+1)
constraints=sum(e["rows"] for e in values(entries))+first_rows+comfort+2n^2+3
prior=r["initial_point_audit"]
variables==prior["variables"] || error("Variable reconstruction differs")
constraints==sum(g["count"] for g in values(prior["groups"])) ||
    error("Constraint reconstruction differs")
costterms=sum(e["nonzero_cost_terms"] for e in values(entries))
report=Dict(
    "schema"=>"r9-risk-structure-audit-v1",
    "origin"=>"synthetic",
    "optimization_performed"=>false,
    "performance_cause_proved"=>false,
    "case_sha256"=>c.sha256,
    "common_sha256"=>S.hashfile(joinpath(common, "manifest.toml")),
    "original_result_sha256"=>S.hashfile(joinpath(run, "run/result.toml")),
    "variables"=>variables,
    "constraints"=>constraints,
    "scenarios"=>n,
    "declared_bound_rows"=>sum(e["declared_bound_rows"] for e in values(entries)),
    "explicit_cost_row_terms"=>n*costterms,
    "auxiliary_cost_equality_terms"=>costterms+n,
    "auxiliary_cost_transport_score_terms"=>n^2,
    "scope"=>"exact structural counts; proposed auxiliary representation not implemented or benchmarked",
    "entries"=>entries,
)
mkpath(out)
S.toml(joinpath(out, "structure.toml"), report)
cp(@__FILE__, joinpath(out, "audit-source.jl"))
S.toml(joinpath(out, "files.toml"), Dict(p=>S.hashfile(joinpath(out, p)) for p in readdir(out)))
println(
    "Reconstructed original ",
    variables,
    " variables / ",
    constraints,
    " rows. Structural counts only, no solve.",
)
