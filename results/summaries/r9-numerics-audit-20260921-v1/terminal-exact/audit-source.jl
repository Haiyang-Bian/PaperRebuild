# 对已保存的Float64线性系统作精确有理数消元。只解释该数值系统，不将其等同于理想实数物理模型。
using CSV, TOML, SHA
function audit_terminal_exact(source, output)
ispath(output) && error("不覆盖精确审计")
meta = TOML.parsefile(joinpath(source, "audit.toml"))
nr, nc = meta["rows"], meta["columns"]
A = zeros(Rational{BigInt}, nr, nc + 1)
for row in CSV.File(joinpath(source, "terminal-matrix.csv"))
    A[row.row, row.column] = Rational{BigInt}(row.coefficient)
end
for row in CSV.File(joinpath(source, "terminal-rhs.csv"))
    A[row.row, end] = Rational{BigInt}(row.rhs)
end
original = copy(A)
transform = zeros(Rational{BigInt}, nr, nr)
for i in 1:nr
    transform[i,i] = 1
end
start = time()
pivots = NamedTuple[]
r = 1
complete = true
for column in 1:nc
    if time() - start > 60
        complete = false
        break
    end
    candidates = [i for i in r:nr if A[i,column] != 0]
    isempty(candidates) && continue
    selected = candidates[argmax(abs(Float64(A[i,column])) for i in candidates)]
    A[r,:], A[selected,:] = copy(A[selected,:]), copy(A[r,:])
    transform[r,:], transform[selected,:] = copy(transform[selected,:]), copy(transform[r,:])
    pivot = A[r,column]
    push!(pivots, (row = r, column = column, magnitude = abs(Float64(pivot))))
    A[r,:] ./= pivot
    transform[r,:] ./= pivot
    for i in r+1:nr
        a = A[i,column]
        a == 0 && continue
        A[i,:] .-= a .* A[r,:]
        transform[i,:] .-= a .* transform[r,:]
    end
    r += 1
end
contradictions = complete ? [i for i in 1:nr if all(iszero, A[i,1:nc]) && !iszero(A[i,end])] : Int[]
mkpath(output)
CSV.write(joinpath(output, "pivots.csv"), pivots)
basis_max = NaN
if complete
    free_columns = setdiff(collect(1:nc), [p.column for p in pivots])
    N = zeros(Rational{BigInt}, nc, length(free_columns))
    for (j,col) in enumerate(free_columns)
        N[col,j] = 1
    end
    for p in reverse(pivots), j in eachindex(free_columns)
        N[p.column,j] = -sum(A[p.row,k]*N[k,j] for k in p.column+1:nc; init=Rational{BigInt}(0))
    end
    all(sum(original[i,k]*N[k,j] for k in 1:nc) == 0 for i in 1:nr, j in eachindex(free_columns)) || error("精确零空间核查失败")
    basis_max = maximum(abs.(Float64.(N)); init=0.0)
    CSV.write(joinpath(output,"nullspace.csv"),[(coordinate=i, free_column=free_columns[j], numerator=string(numerator(N[i,j])), denominator=string(denominator(N[i,j])), approximate=Float64(N[i,j])) for i in 1:nc for j in eachindex(free_columns)])
end
certificate = false
if !isempty(contradictions)
    i = first(contradictions)
    y = transform[i,:]
    check = [sum(y[k]*original[k,j] for k in 1:nr) for j in 1:nc+1]
    certificate = all(iszero, check[1:nc]) && check[end] != 0
    open(joinpath(output, "contradiction.toml"), "w") do io
        TOML.print(io, Dict("weights_numerator" => string.(numerator.(y)),
            "weights_denominator" => string.(denominator.(y)),
            "rhs_numerator" => string(numerator(check[end])),
            "rhs_denominator" => string(denominator(check[end])),
            "exact_float_system_only" => true); sorted = true)
    end
end
report = Dict("schema" => "r9-terminal-exact-audit-v1", "input_sha256" => meta["input_sha256"],
    "completed" => complete, "rank_if_completed" => length(pivots), "contradiction_count" => length(contradictions),
    "nullspace_max_coefficient" => basis_max,
    "exact_certificate_checked" => certificate, "elapsed_sec" => time()-start,
    "interpretation" => "Exact rational arithmetic on saved binary floating-point coefficients; not a physical impossibility certificate",
    "source_matrix_sha256" => bytes2hex(sha256(read(joinpath(source, "terminal-matrix.csv")))),
    "source_rhs_sha256" => bytes2hex(sha256(read(joinpath(source, "terminal-rhs.csv")))))
open(io -> TOML.print(io, report; sorted = true), joinpath(output, "audit.toml"), "w")
cp(@__FILE__, joinpath(output, "audit-source.jl"))
println(report)
end
length(ARGS) == 2 || error("usage: audit_r9_terminal_exact.jl MATRIX_AUDIT NEW_OUTPUT")
audit_terminal_exact(ARGS...)
