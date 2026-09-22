# 只读分析终端仿射关系，不删约束、不改秩阈值，也不求解调度。
using PaperRebuild, JuMP, LinearAlgebra, TOML, CSV, SHA
length(ARGS) == 2 || error("usage: audit_r9_terminal.jl CASE NEW_OUTPUT")
casepath, out = ARGS
ispath(out) && error("不覆盖终端审计")
c = load_r9_pv_case(casepath)
b = build_r9_reduced_model(c; mode = :CF_VT)
h = c.data["heat"]
sources = findall(n -> n["role"] == "source", h["nodes"])
coordinates = [(j, t) for j in sources for t in 1:c.data["T"]]
vars = [
    only(x for (a, x) in linear_terms(b.variables["tau_S_port"][j, t]) if a != 0) for
    (j, t) in coordinates
]
refs = b.constraints["R9-P6"]
A = [coefficient(constraint_object(cr).func, x) for cr in refs, x in vars]
rhs = [constraint_object(cr).set.value - constant(constraint_object(cr).func) for cr in refs]
baseline = fill(h["S_reference_K"] - b.temperature_centre_K, length(vars))
decomposition = svd(A)
s = decomposition.S
mkpath(out)
CSV.write(
    joinpath(out, "singular-values.csv"),
    [(i = i, singular_value = s[i], relative = s[i]/s[1]) for i in eachindex(s)],
)
CSV.write(
    joinpath(out, "terminal-matrix.csv"),
    [
        (
            row = i,
            column = k,
            source = coordinates[k][1],
            t = coordinates[k][2],
            coefficient = A[i, k],
        ) for i in axes(A, 1) for k in axes(A, 2)
    ],
)
CSV.write(
    joinpath(out, "terminal-rhs.csv"),
    [(row = i, rhs = rhs[i], reference_residual = (A*baseline-rhs)[i]) for i in eachindex(rhs)],
)
summary = Dict{String,Any}(
    "schema" => "r9-terminal-conditioning-v1",
    "input_sha256" => c.sha256,
    "rows" => size(A, 1),
    "columns" => size(A, 2),
    "reference_max_residual_K" => maximum(abs, A*baseline-rhs),
    "rank_default_diagnostic_only" => rank(A),
    "singular_values" => s,
    "smallest_nonzero_coefficient" => minimum(abs(x) for x in A if x != 0),
    "largest_coefficient" => maximum(abs, A),
    "source_sha256" => bytes2hex(sha256(read(@__FILE__))),
)
open(io -> TOML.print(io, summary; sorted = true), joinpath(out, "audit.toml"), "w")
cp(@__FILE__, joinpath(out, "audit-source.jl"))
println(summary)
