# R7-H1至H4：沿累计质量标签积分散热；节点仍采用时段平均混合。
# Gauss–Legendre节点/权重与余项依据NIST DLMF 3.5.E19/E21、表3.5.1/2。
function r7_gauss_unit(order)
    if order == 5
        x = [-0.9061798459386640, -0.5384693101056831, 0.0, 0.5384693101056831, 0.9061798459386640]
        w = [
            0.2369268850561891,
            0.4786286704993665,
            0.5688888888888889,
            0.4786286704993665,
            0.2369268850561891,
        ]
    elseif order == 10
        p = [
            0.14887433898163121,
            0.43339539412924719,
            0.67940956829902441,
            0.86506336668898451,
            0.97390652851717172,
        ]
        v = [
            0.29552422471475287,
            0.26926671930999636,
            0.21908636251598204,
            0.14945134915058059,
            0.06667134430868814,
        ]
        x, w = vcat(-reverse(p), p), vcat(reverse(v), v)
    else
        error("有损输运只声明5或10点Gauss积分")
    end
    (x .+ 1) ./ 2, w ./ 2
end

"""
    r7_loss_quadrature_bound(beta_max, temperature_span; order=10)

R7-H4有损质量积分的解析截断误差上界。beta_max为各步UA*3600Δt/(M*c)的最大值，
temperature_span为初态、入口及环境温度共同取值区间宽度。返回出口平均温度及单位质量库存
的保守误差上界，单位与temperature_span相同。它不包含浮点、求解容差或网络传播误差，
不能替代独立水团回放；不是原论文新增精度保证。仅支持5/10点积分。
"""
function r7_loss_quadrature_bound(beta_max, temperature_span; order = 10)
    r7_gauss_unit(order)
    all(isfinite, (beta_max, temperature_span)) && beta_max >= 0 && temperature_span >= 0 ||
        error("散热指数与温区宽度必须非负有限")
    # [0,1]上exp(a+d*u)的n点余项：exp(max(a,a+d))*d^(2n)*(n!)^4/((2n+1)*(2n)!^3)。
    b, span = BigFloat(beta_max), BigFloat(temperature_span)
    k = BigFloat(factorial(big(order)))^4 / ((2order+1)*BigFloat(factorial(big(2order)))^3)
    Float64(span*exp(b)*k*(b^(2order)+(2b)^(2order)))
end

# 各自把对方区间裁剪到自身区间；空交集时两组端点无需相同，但积分宽度严格为零。
function r7_loss_slice!(m, a, b, c, d, tag)
    left = r7_positive_part!(m, c-a, tag*"_la") - r7_positive_part!(m, c-b, tag*"_lb")
    right = r7_positive_part!(m, d-a, tag*"_ra") - r7_positive_part!(m, d-b, tag*"_rb")
    left, right
end

function r7_loss_fraction!(m, x, q, tag)
    q isa Real && return q == 0 ? 0.0 : x/q
    u = @variable(m, lower_bound = 0, upper_bound = 1, base_name = tag)
    @constraint(m, q*u == x)
    u
end

function r7_loss_exp!(m, x, lo, hi, tag)
    x isa Real && return exp(x)
    y = @variable(m, lower_bound = exp(lo), upper_bound = exp(hi), base_name = tag)
    @constraint(m, y == exp(x))
    y
end

function r7_loss_mean_exp!(m, a, b, gauss, lower, upper, tag)
    if a isa Real && b isa Real
        return sum(w*exp((1-u)*a+u*b) for (u, w) in zip(gauss...))
    end
    sum(
        w*r7_loss_exp!(m, (1-u)*a+u*b, lower, upper, "$(tag)_$i") for
        (i, (u, w)) in enumerate(zip(gauss...))
    )
end

function r7_loss_temperature!(m, x, lo, hi, tag)
    x isa Real && return x
    y = @variable(m, lower_bound = lo, upper_bound = hi, base_name = tag)
    @constraint(m, y == x)
    y
end

# R9-RI2：源标签与初始空间坐标方向相反；sl/sr由源区间左端起算。
function r7_initial_exponents(s, mass, sl, sr)
    s.from_left ? (-s.rate*(mass-sl), -s.rate*(mass-sr)) : (-s.rate*sl, -s.rate*sr)
end

function r7_initial_spatial_check(mass, means, spatial, lo, hi)
    spatial===nothing && return (;
        base = Float64.(means),
        amplitude = zeros(length(means)),
        span = 0.0,
        amplitude_max = 0.0,
    )
    length(spatial)==length(mass) || error("指数初态段数错误")
    for (w, mean, s) in zip(mass, means, spatial)
        all(isfinite, (s.base, s.amplitude, s.rate)) && s.rate>=0 && s.from_left isa Bool ||
            error("指数初态参数错误")
        endpoints=(s.base+s.amplitude, s.base+s.amplitude*exp(-s.rate*w))
        all(x->lo<=x<=hi, endpoints) || error("指数初态真实端点越界")
        exact=s.base+s.amplitude*(s.rate==0 ? 1.0 : -expm1(-s.rate*w)/(s.rate*w))
        abs(exact-mean)<=1e-10 || error("初态均值与空间分布不一致")
    end
    (;
        base = [s.base for s in spatial],
        amplitude = [s.amplitude for s in spatial],
        span = maximum(s.rate*w for (s, w) in zip(spatial, mass)),
        amplitude_max = maximum(abs(s.amplitude) for s in spatial),
    )
end

# R9-RI3：初态空间指数和当步时间指数共同进入积分误差；供输入预检与建模共用。
function r7_initial_quadrature_bound(beta, shape, ambient, lo, hi; order = 10)
    low, high=min(lo, minimum(ambient)), max(hi, maximum(ambient))
    bound=r7_loss_quadrature_bound(beta, high-low; order)
    shape===nothing && return bound
    base_span=maximum(abs.(shape.base .- ambient'))
    bound+r7_loss_quadrature_bound(beta+shape.span, base_span+shape.amplitude_max; order)
end

"""
    add_r7_lossy_mass_transport!(model, q, theta_in, theta_out, inventory,
        initial_mass, initial_theta; dt_h, decay_per_h, ambient, order=10,
        max_truncation_error=1e-10, temperature_bounds=(0.0,1.0), prefix="lossy", deadline=Inf,
        initial_spatial=nothing)

R7-H1至H4：加入正向/停流有损塞流的累计质量表达式，不求解或写文件。q为每步通过质量/管内质量，
dt_h可为不同正步长，decay_per_h=3600UA/(M*c)，ambient和温度使用同一归一化标度。
初态按入口至出口排列，initial_mass之和为1；默认使用分段常温。显式initial_spatial逐段给出
归一化base、amplitude、rate及from_left，按R9-RI1/RI2保留指数空间分布；initial_theta必须为
该段精确均值，不能另给不一致均温。每步入口、环境及流量常值；不取整时延。
使用有解析截断界的Gauss积分；显式拒绝超界参数。指数保留为非线性约束，不宣称模型仍为MIQCP。
零流不除以流量、出口温度无观测意义，但库存继续散热。保留水团两端受temperature_bounds约束；
不限制已经离管的水团。loss返回按整管质量及温度标度归一化的散热，可为负（环境供热）。
UA=0且无指数初态时直接使用原无损质量核；指数初态即使UA=0仍需空间积分及误差验收。
独立验证仍须调用r7_pipe_step，不能用本核重算自身作为物理证明。
"""
function add_r7_lossy_mass_transport!(
    m,
    q,
    θin,
    θout,
    inventory,
    initial_mass,
    initial_θ;
    dt_h,
    decay_per_h,
    ambient,
    order = 10,
    max_truncation_error = 1e-10,
    temperature_bounds = (0.0, 1.0),
    prefix = "lossy",
    deadline = Inf,
    initial_spatial = nothing,
)
    T = length(q)
    T > 0 &&
    length(θin) == length(θout) == length(dt_h) == length(ambient) == T &&
    length(inventory) == T+1 || error("有损输运维度错误")
    all(x -> isfinite(x) && x > 0, dt_h) &&
    all(isfinite, ambient) &&
    isfinite(decay_per_h) &&
    decay_per_h >= 0 || error("散热/步长输入错误")
    lo, hi = temperature_bounds
    all(isfinite, (lo, hi, max_truncation_error)) && lo < hi && max_truncation_error > 0 ||
        error("温区或截断界错误")
    length(initial_mass) == length(initial_θ) > 0 &&
    all(x -> isfinite(x) && x > 0, initial_mass) &&
    abs(sum(initial_mass)-1) <= 1e-10 &&
    all(x -> isfinite(x) && lo <= x <= hi, initial_θ) || error("初始质量/温度错误")
    all(first(r7_affine_interval(x)) >= 0 for x in q) || error("此有损质量核不允许反向流")
    all(lo <= first(r7_affine_interval(x)) <= last(r7_affine_interval(x)) <= hi for x in θin) ||
        error("入口温度须有声明的有限界")
    β = decay_per_h .* dt_h
    all(isfinite, β) || error("散热指数溢出")
    low, high = min(lo, minimum(ambient)), max(hi, maximum(ambient))
    shape=r7_initial_spatial_check(initial_mass, initial_θ, initial_spatial, lo, hi)
    # 初态幅值可能大于物理温区（base可为环境温度）；按实际系数另计误差，不能只看段均值。
    bound = r7_initial_quadrature_bound(
        maximum(β),
        initial_spatial===nothing ? nothing : shape,
        ambient,
        lo,
        hi;
        order,
    )
    bound <= max_truncation_error || error("有损积分截断上界超出预定门槛，不自动放宽")
    gauss = r7_gauss_unit(order)
    if decay_per_h == 0 && temperature_bounds == (0.0, 1.0) && initial_spatial===nothing
        z = add_r7_mass_transport!(
            m,
            q,
            θin,
            θout,
            inventory,
            initial_mass,
            initial_θ;
            prefix,
            deadline,
            allow_zero = true,
        )
        return (; z..., loss = zeros(T), quadrature_bound = bound, nonlinear_loss = false)
    end
    C = [sum(q[1:t]; init = 0.0) for t in 0:T]
    times = vcat(0.0, cumsum(dt_h))
    edges = vcat(0.0, cumsum(initial_mass))
    n = length(initial_mass)
    starts = Any[-edges[j+1] for j in 1:n]
    ends = Any[-edges[j] for j in 1:n]
    append!(starts, C[1:T])
    append!(ends, C[2:(T+1)])
    # 无入口幅值时的环境响应；对每个出生时段单独递推，环境可逐步改变。
    background = zeros(T, T)
    for j in 1:T
        background[j, j] = ambient[j]
        for t in (j+1):T
            background[j, t] = ambient[t]+(background[j, t-1]-ambient[t])*exp(-β[t])
        end
    end
    initial = hcat(shape.base, zeros(n, T))
    for t in 1:T
        initial[:, t+1] = ambient[t] .+ (initial[:, t] .- ambient[t])*exp(-β[t])
    end
    @constraint(m, inventory[1] == sum(initial_mass .* initial_θ))
    loss = Any[]
    segments = Any[]
    for t in 1:T
        time() < deadline || error("lossy_transport_build_deadline")
        out_terms, inv_terms = Any[], Any[]
        for j in 1:(n+t)
            time() < deadline || error("lossy_transport_build_deadline")
            born = j-n
            # 已知零流源没有水团；变流量可等于零时则由零交集使所有贡献为零。
            born > 0 && q[born] isa Real && q[born] == 0 && continue
            a, b = starts[j], ends[j]
            for mode in (:out, :inventory)
                mode == :out && q[t] isa Real && q[t] == 0 && continue
                c, d = mode == :out ? (C[t]-1, C[t+1]-1) : (C[t+1]-1, C[t+1])
                tag = "$(prefix)_$(mode)_$(t)_$j"
                sl, sr = r7_loss_slice!(m, a, b, c, d, tag*"_source")
                width = sr-sl
                width isa Real && width <= 0 && continue
                if born > 0
                    ul = r7_loss_fraction!(m, sl, q[born], tag*"_in_l")
                    ur = r7_loss_fraction!(m, sr, q[born], tag*"_in_r")
                end
                if mode == :out
                    tl, tr = r7_loss_slice!(m, c, d, a, b, tag*"_exit")
                    vl = r7_loss_fraction!(m, tl, q[t], tag*"_out_l")
                    vr = r7_loss_fraction!(m, tr, q[t], tag*"_out_r")
                    z = r7_loss_mean_exp!(m, -β[t]*vl, -β[t]*vr, gauss, -β[t], 0.0, tag*"_age")
                    if born <= 0
                        expr = ambient[t]+(initial[j, t]-ambient[t])*z
                        if initial_spatial!==nothing && shape.amplitude[j]!=0
                            el, er=r7_initial_exponents(initial_spatial[j], initial_mass[j], sl, sr)
                            spatial=r7_loss_mean_exp!(
                                m,
                                el-β[t]*vl,
                                er-β[t]*vr,
                                gauss,
                                -initial_spatial[j].rate*initial_mass[j]-β[t],
                                0.0,
                                tag*"_initial",
                            )
                            expr += shape.amplitude[j]*exp(-decay_per_h*times[t])*spatial
                        end
                    else
                        B = born == t ? ambient[t] : background[born, t-1]
                        age = decay_per_h*(times[t]-times[born])
                        e = r7_loss_mean_exp!(
                            m,
                            -age+β[born]*ul-β[t]*vl,
                            -age+β[born]*ur-β[t]*vr,
                            gauss,
                            -age-β[t],
                            β[born],
                            tag*"_entry",
                        )
                        expr = ambient[t]+(B-ambient[t])*z+(θin[born]-ambient[born])*e
                    end
                    avg =
                        r7_loss_temperature!(m, expr, low-(high-low), high+(high-low), tag*"_mean")
                    push!(out_terms, width*avg)
                else
                    if born <= 0
                        avg = initial[j, t+1]
                        endpoint = (avg, avg)
                        if initial_spatial!==nothing && shape.amplitude[j]!=0
                            el, er=r7_initial_exponents(initial_spatial[j], initial_mass[j], sl, sr)
                            lower=-initial_spatial[j].rate*initial_mass[j]
                            spatial=r7_loss_mean_exp!(m, el, er, gauss, lower, 0.0, tag*"_initial")
                            amp=shape.amplitude[j]*exp(-decay_per_h*times[t+1])
                            endpoint=Tuple(
                                initial[j, t+1]+amp*r7_loss_exp!(
                                    m,
                                    e,
                                    lower,
                                    0.0,
                                    tag*"_initial_endpoint_$k",
                                ) for (k, e) in enumerate((el, er))
                            )
                            avg += amp*spatial
                        end
                    else
                        age = decay_per_h*(times[t+1]-times[born])
                        el, er = -age+β[born]*ul, -age+β[born]*ur
                        z = r7_loss_mean_exp!(m, el, er, gauss, -age, 0.0, tag*"_entry")
                        B, amplitude = background[born, t], θin[born]-ambient[born]
                        avg = r7_loss_temperature!(m, B+amplitude*z, low, high, tag*"_mean")
                        endpoint = Tuple(
                            r7_loss_temperature!(
                                m,
                                B+amplitude*r7_loss_exp!(m, e, -age, 0.0, tag*"_endpoint_$k"),
                                low,
                                high,
                                tag*"_temp_$k",
                            ) for (k, e) in enumerate((el, er))
                        )
                    end
                    # 空交集不约束不存在的水团；非零保留质量必须满足完整段的两端温区。
                    for endpoint_temp in endpoint
                        @constraint(m, width*(endpoint_temp-lo) >= 0)
                        @constraint(m, width*(hi-endpoint_temp) >= 0)
                    end
                    push!(inv_terms, width*avg)
                    push!(segments, (; time = t, cohort = j, width, endpoint))
                end
            end
        end
        @constraint(m, q[t]*θout[t] == sum(out_terms; init = 0.0))
        @constraint(m, inventory[t+1] == sum(inv_terms; init = 0.0))
        push!(loss, q[t]*(θin[t]-θout[t])-inventory[t+1]+inventory[t])
    end
    (; cumulative = C, loss, segments, quadrature_bound = bound, nonlinear_loss = true)
end
