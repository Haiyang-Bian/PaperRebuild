"""
    r9_terminal_coordinates(A, rhs, lower, upper)

对固定流量的终端系统Aθ=rhs作精确二进制有理数消元（R9-F1—F2）。
不读取参考调度、费用或作者结果；保留全部非零主元，不按奇异值截断自由方向。
用512位正交化生成完整核空间；常数点由输入源温盒中心及预先给定误差界的Tikhonov线性系统决定，
避免极小非零奇异方向将舍入误差放大成无界温度。正则权重为(1e-10/(4max(1,源温盒半径)))²。
再以原二进制系数精确回代所有行给出误差界；不按结果选权重，不只挑一组独立行。
只有全部源温边界内的终端偏差不超过1e-10 K时才返回；有意义的不相容流量明确拒绝。
这是显式的受界舍入解释，不宣称与存在矛盾的字面Float64等式完全相同。
返回offset、basis和证书；不修改模型、不求解、不写文件，不能独立认证参数灵敏度。
"""
function r9_terminal_coordinates(A, rhs, lower, upper)
    nr, nc = size(A)
    length(rhs) == nr && length(lower) == nc && length(upper) == nc ||
        throw(ArgumentError("终端系统形状不一致"))
    all(isfinite, A) &&
    all(isfinite, rhs) &&
    all(isfinite, lower) &&
    all(isfinite, upper) &&
    all(lower .<= upper) || throw(ArgumentError("终端系数或源温边界非法"))
    exactA, exactb = Rational{BigInt}.(A), Rational{BigInt}.(rhs)
    R = hcat(exactA, exactb)
    pivots = Int[]
    row = 1
    for col in 1:nc
        candidates = [i for i in row:nr if R[i, col] != 0]
        isempty(candidates) && continue
        selected = candidates[argmax(abs(R[i, col]) for i in candidates)]
        R[row, :], R[selected, :] = copy(R[selected, :]), copy(R[row, :])
        R[row, :] ./= R[row, col]
        for i in (row+1):nr
            factor = R[i, col]
            iszero(factor) || (R[i, :] .-= factor .* R[row, :])
        end
        push!(pivots, col)
        row += 1
    end
    free = setdiff(collect(1:nc), pivots)
    N = zeros(Rational{BigInt}, nc, length(free))
    p = zeros(Rational{BigInt}, nc)
    for (j, col) in enumerate(free)
        N[col, j] = 1
    end
    for i in reverse(eachindex(pivots))
        col = pivots[i]
        p[col] = R[i, end] - sum(R[i, k]*p[k] for k in (col+1):nc; init = Rational{BigInt}(0))
        for j in eachindex(free)
            N[col, j] = -sum(R[i, k]*N[k, j] for k in (col+1):nc; init = Rational{BigInt}(0))
        end
    end
    all(iszero, exactA*N) || error("完整核空间的精确认证失败")
    offset, basis = setprecision(BigFloat, 512) do
        Q = zeros(BigFloat, size(N))
        for j in axes(N, 2)
            q = BigFloat.(N[:, j])
            for _ in 1:2, k in 1:(j-1)
                q .-= sum(Q[:, k] .* q) .* Q[:, k]
            end
            magnitude = sqrt(sum(abs2, q))
            magnitude > 0 || error("完整核空间正交化失败")
            Q[:, j] = q ./ magnitude
        end
        # 输入盒中心而非参考调度。若某个盒内点严格可行，此权重给出≤误差界/4的残差上界；
        # 不假定该点存在，后面仍逐行拒绝超界。全部非零核方向由精确秩保留。
        reference = (BigFloat.(lower)+BigFloat.(upper))/2
        box_radius = sqrt(sum(abs2, (BigFloat.(upper)-BigFloat.(lower))/2))
        weight = (BigFloat(1e-10)/(4max(BigFloat(1), box_radius)))^2
        B = BigFloat.(exactA)
        mismatch = BigFloat.(exactb)-B*reference
        G = B'*B
        gradient = B'*mismatch
        for i in 1:nc
            G[i, i] += weight
        end
        # 小型正定线性系统的Cholesky运算；不调用优化器，不截断小主元。
        L = zeros(BigFloat, nc, nc)
        for i in 1:nc, j in 1:i
            x = G[i, j]-sum(L[i, k]*L[j, k] for k in 1:(j-1); init = BigFloat(0))
            if i==j
                x>0 || error("终端正则线性系统丢失正定性")
                L[i, j]=sqrt(x)
            else
                L[i, j]=x/L[j, j]
            end
        end
        z, delta=zeros(BigFloat, nc), zeros(BigFloat, nc)
        for i in 1:nc
            z[i]=(gradient[i]-sum(L[i, k]*z[k] for k in 1:(i-1); init = BigFloat(0)))/L[i, i]
        end
        for i in reverse(1:nc)
            delta[i]=(z[i]-sum(L[k, i]*delta[k] for k in (i+1):nc; init = BigFloat(0)))/L[i, i]
        end
        p0=reference+delta
        Float64.(p0), Float64.(Q)
    end
    gram_error = maximum(
        sum(abs(sum(basis[:, i] .* basis[:, j]) - Int(i == j)) for j in axes(basis, 2)) for
        i in axes(basis, 2);
        init = 0.0,
    )
    gram_error < 1e-10 || error("核空间转换缺少正交性")
    radius =
        sqrt(
            sum(max(abs(lower[i]-offset[i]), abs(upper[i]-offset[i]))^2 for i in 1:nc; init = 0.0),
        ) / sqrt(1-gram_error) * (1+1e-12)
    offset_error = exactA*Rational{BigInt}.(offset)-exactb
    kernel_error = exactA*Rational{BigInt}.(basis)
    bounds = [
        Float64(abs(offset_error[i])) +
        radius*Float64(sum(abs, kernel_error[i, :]; init = Rational{BigInt}(0))) for i in 1:nr
    ]
    maximum(bounds; init = 0.0) <= 1e-10 || throw(
        ArgumentError(
            "固定流量终端不相容：完整源温域误差界$(maximum(bounds)) K超过1e-10 K；不能重新锚定",
        ),
    )
    return (;
        offset,
        basis,
        rank = length(pivots),
        radius,
        gram_error,
        offset_error_K = Float64.(offset_error),
        row_error_bound_K = bounds,
        exact_binary_consistent = all(iszero, exactA*p-exactb),
        free_columns = free,
        regularization_weight = (1e-10/(4max(1.0, sqrt(sum(abs2, (upper-lower)/2)))))^2,
    )
end

# 保留全部源温坐标的显式数值区间；不借源温锚定或奇异值截断消除物理控制方向。
function r9_band_fixed_terminal(b)
    model=b.model
    radius=2.0^-34
    rows=NamedTuple[]
    for cr in get(b.constraints, "R9-P6", Any[])
        obj=constraint_object(cr)
        obj.set isa MOI.EqualTo || error("终端行应为等式")
        rhs=obj.set.value
        lower, upper=rhs-radius, rhs+radius
        max(
            abs(Rational{BigInt}(lower)-Rational{BigInt}(rhs)),
            abs(Rational{BigInt}(upper)-Rational{BigInt}(rhs)),
        )<=Rational{BigInt}(1e-10) || error("终端区间的浮点表示超过解释界")
        r2_add!(b.constraints, "R9-F3-terminal-band", @constraint(model, obj.func>=lower))
        r2_add!(b.constraints, "R9-F3-terminal-band", @constraint(model, obj.func<=upper))
        push!(rows, (; rhs, lower, upper))
        delete(model, cr)
    end
    delete!(b.constraints, "R9-P6")
    constants=[x.residual for x in b.constant_checks if x.equation=="R9-P6"]
    maximum(constants; init = 0.0)<=radius || throw(ArgumentError("常数终端超出数值区间"))
    cert=Dict{String,Any}(
        "method"=>"roundoff_band",
        "radius_K"=>radius,
        "interpretation_error_limit_K"=>1e-10,
        "reference_witness_used"=>false,
        "terminal_rows"=>[Dict(string(k)=>getproperty(x, k) for k in keys(x)) for x in rows],
        "maximum_constant_terminal_residual_K"=>maximum(constants; init = 0.0),
    )
    return merge(
        b,
        (; terminal_certificate = cert, variant = replace(b.variant, "forward"=>"roundoff_band")),
    )
end

function r9_parameterize_fixed_terminal(c, b, mode)
    model, h, T = b.model, c.data["heat"], c.data["T"]
    coordinates = [(j, t) for (j, n) in enumerate(h["nodes"]) if n["role"]=="source" for t in 1:T]
    ct = mode in (:CF_CT, :VF_CT)
    sources =
        ct ? VariableRef[] :
        [
            only(x for (a, x) in linear_terms(b.variables["tau_S_port"][j, t]) if a != 0) for
            (j, t) in coordinates
        ]
    refs = get(b.constraints, "R9-P6", Any[])
    A = [coefficient(constraint_object(cr).func, x) for cr in refs, x in sources]
    rhs = [constraint_object(cr).set.value-constant(constraint_object(cr).func) for cr in refs]
    coordinates_data = r9_terminal_coordinates(A, rhs, lower_bound.(sources), upper_bound.(sources))
    U, p = coordinates_data.basis, coordinates_data.offset
    y = @variable(
        model,
        [1:size(U, 2)],
        lower_bound=-coordinates_data.radius,
        upper_bound=coordinates_data.radius
    )
    replacement = Dict(
        sources[i] => p[i]+sum(U[i, j]*y[j] for j in axes(U, 2); init = AffExpr(0.0)) for
        i in eachindex(sources)
    )
    substitute(x::Number) = x
    substitute(x::VariableRef) = get(replacement, x, x)
    substitute(x::AffExpr) =
        constant(x)+sum(a*substitute(v) for (a, v) in linear_terms(x); init = AffExpr(0.0))
    foreach(cr -> delete(model, cr), refs)
    delete!(b.constraints, "R9-P6")
    for constraints in values(b.constraints), i in eachindex(constraints)
        cr = constraints[i]
        obj = constraint_object(cr)
        obj.func isa AffExpr || continue
        any(haskey(replacement, x) for (_, x) in linear_terms(obj.func)) || continue
        constraints[i] = @constraint(model, substitute(obj.func) in obj.set)
        delete(model, cr)
    end
    variables = Dict(k=>map(substitute, array) for (k, array) in b.variables)
    variables["r9_terminal_coordinates"] = y
    for x in sources
        r2_add!(
            b.constraints,
            "R9-F2-source-bound",
            @constraint(model, replacement[x]>=lower_bound(x))
        )
        r2_add!(
            b.constraints,
            "R9-F2-source-bound",
            @constraint(model, replacement[x]<=upper_bound(x))
        )
    end
    delete(model, sources)
    cert = Dict{String,Any}(
        "method"=>"rank_checked_rhs",
        "rank_exact_binary"=>coordinates_data.rank,
        "source_coordinates"=>ct ? Vector{Int}[] : [collect(x) for x in coordinates],
        "free_source_count"=>size(U, 2),
        "free_columns"=>coordinates_data.free_columns,
        "offset_K"=>p,
        "basis"=>[collect(row) for row in eachrow(U)],
        "terminal_matrix"=>[collect(row) for row in eachrow(A)],
        "terminal_rhs_K"=>rhs,
        "exact_binary_consistent"=>coordinates_data.exact_binary_consistent,
        "offset_error_K"=>coordinates_data.offset_error_K,
        "row_error_bound_K"=>coordinates_data.row_error_bound_K,
        "source_coordinate_bound_K"=>coordinates_data.radius,
        "basis_gram_error"=>coordinates_data.gram_error,
        "interpretation_error_limit_K"=>1e-10,
        "reference_witness_used"=>false,
        "offset_rule"=>"input_box_centered_tikhonov_512bit",
        "regularization_weight"=>coordinates_data.regularization_weight,
    )
    return merge(
        b,
        (;
            variables,
            terminal_certificate = cert,
            class = r2_model_class(model),
            variant = replace(b.variant, "forward"=>"rank_checked_rhs"),
        ),
    )
end
