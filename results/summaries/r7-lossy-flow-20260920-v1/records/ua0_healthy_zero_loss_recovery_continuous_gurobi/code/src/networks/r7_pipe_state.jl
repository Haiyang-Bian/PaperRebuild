# 项目参考R7-P1：以固定空间方向排列水质量段，不把出口温度当作全管平均温度。
struct R7PipeSegment
    mass_kg::Float64
    base_K::Float64
    amplitude_K::Float64
    rate_per_kg::Float64
    from_left::Bool
end

"""
    R7PipeState

单根管道的分段温度分布，空间坐标是从给定左端起算的累计水质量kg。
由r7_pipe_state构造；段内温度是常量加单指数，能够保留非整数输运及反向时的旧温度分布。
这是R7-P1项目一维塞流参考，不等同于论文节点法/WMM的离散散热式，也不是水力模型。
"""
struct R7PipeState
    segments::Vector{R7PipeSegment}
end

function r7_pipe_check(s::R7PipeState)
    isempty(s.segments) && error("管道状态不能为空")
    for p in s.segments
        all(isfinite, (p.mass_kg, p.base_K, p.amplitude_K, p.rate_per_kg)) &&
        p.mass_kg>0 &&
        p.rate_per_kg>=0 || error("管段质量或温度参数非法")
        min(p.base_K+p.amplitude_K, p.base_K+p.amplitude_K*exp(-p.rate_per_kg*p.mass_kg))>0 ||
            error("绝对温度必须为正")
    end
    M=sum(p.mass_kg for p in s.segments)
    isfinite(M) && M>0 || error("管内容水质量非法")
    M
end

"""
    r7_pipe_state(masses_kg, temperatures_K)

从显式初始分段质量与温度建立管内状态；质量kg、温度K，两向量按空间左至右排列。
不按入口/出口温度猜测初始历史，输入与原件关系由调用者登记。对应R7-P1。
"""
function r7_pipe_state(masses_kg, temperatures_K)
    length(masses_kg)==length(temperatures_K)>0 || error("初始质量和温度维度不同")
    s=R7PipeState([
        R7PipeSegment(Float64(m), Float64(T), 0.0, 0.0, true) for
        (m, T) in zip(masses_kg, temperatures_K)
    ])
    r7_pipe_check(s)
    s
end

# 线性指数在两端均不大于零；避免反向流动时构造exp(很大正数)。
function r7_exp_integral(length_kg, e0, e1)
    d=abs(e1-e0)
    length_kg*exp(max(e0, e1))*(d==0 ? 1.0 : -expm1(-d)/d)
end
function r7_segment_integral(p, a, b, reference; e0 = 0.0, e1 = 0.0)
    f(x) = -p.rate_per_kg*(p.from_left ? x : p.mass_kg-x)
    (p.base_K-reference)*r7_exp_integral(b-a, e0, e1) +
    p.amplitude_K*r7_exp_integral(b-a, e0+f(a), e1+f(b))
end
function r7_pipe_integral(s, lo, hi, reference; exponent = x->0.0)
    result, offset=0.0, 0.0
    for p in s.segments
        a, b=max(0.0, lo-offset), min(p.mass_kg, hi-offset)
        if b>a
            result+=r7_segment_integral(
                p,
                a,
                b,
                reference;
                e0 = exponent(offset+a),
                e1 = exponent(offset+b),
            )
        end
        offset+=p.mass_kg
    end
    result
end

"""
    r7_pipe_temperature(state, mass_coordinate_kg)

查询管内给定空间质量坐标的温度K。内部分段边界取右侧，最右端取最后一段。
它是时刻温度，区别于r7_pipe_step返回的整个时间步出口平均温度；对应R7-P1/P3。
"""
function r7_pipe_temperature(s::R7PipeState, x)
    M=r7_pipe_check(s)
    isfinite(x)&&0<=x<=M || error("查询坐标超出管道")
    offset=0.0
    for (i, p) in enumerate(s.segments)
        if x<offset+p.mass_kg || i==length(s.segments)
            local_x=clamp(x-offset, 0.0, p.mass_kg)
            distance=p.from_left ? local_x : p.mass_kg-local_x
            return p.base_K+p.amplitude_K*exp(-p.rate_per_kg*distance)
        end
        offset+=p.mass_kg
    end
    error("未找到温度区间")
end

"""
    r7_pipe_inventory(state; cp_J_kgK, reference_K)

按R7-P2积分整管质量平均温度与相对reference_K的显热MWh。
cp使用J/(kg K)，显式除以3.6e9。相对显热可为负，不能直接称为可全部回收的供热量。
它为原式(6-90)提供状态核算参考，尚不认证正常调度、混合或灾后可回收性。
"""
function r7_pipe_inventory(s::R7PipeState; cp_J_kgK, reference_K)
    M=r7_pipe_check(s)
    isfinite(cp_J_kgK)&&cp_J_kgK>0&&isfinite(reference_K)&&reference_K>0 ||
        error("比热或参考温度非法")
    relative=r7_pipe_integral(s, 0.0, M, Float64(reference_K))
    mean_K=Float64(reference_K)+relative/M
    energy=Float64(cp_J_kgK)/3.6e9*relative
    all(isfinite, (mean_K, energy)) || error("显热积分溢出")
    (; mass_kg = M, mean_K, relative_heat_MWh = energy)
end

function r7_pipe_survivors(s, lo, hi, ambient, decay)
    out=R7PipeSegment[]
    offset=0.0
    for p in s.segments
        a, b=max(0.0, lo-offset), min(p.mass_kg, hi-offset)
        if b>a
            distance=p.from_left ? a : p.mass_kg-b
            push!(
                out,
                R7PipeSegment(
                    b-a,
                    ambient+(p.base_K-ambient)*decay,
                    p.amplitude_K*exp(-p.rate_per_kg*distance)*decay,
                    p.rate_per_kg,
                    p.from_left,
                ),
            )
        end
        offset+=p.mass_kg
    end
    out
end

"""
    r7_pipe_step(state; mass_flow_kg_s, inlet_K=nothing, ambient_K, dt_h,
                 cp_J_kgK, UA_W_K, reference_K)

R7-P3/P4的一维平流—散热参考步进：每步流率、入口及环境温度恒定；均匀传热UA为W/K。
正流从左端进入，负流从右端进入；停流时仍冷却且无出口平均温度（返回nothing）。
返回新状态、出口时间平均温度及独立积分的进/出显热和散热MWh。管壁热容、轴向导热、
水力和节点混合未包含；不调用求解器、不写文件、不更改输入。散热为负代表环境供热。
非整数延迟由实际质量段裁切处理，不取整；时间步h显式转秒。供回水须分别调用。
"""
function r7_pipe_step(
    s::R7PipeState;
    mass_flow_kg_s,
    inlet_K = nothing,
    ambient_K,
    dt_h,
    cp_J_kgK,
    UA_W_K,
    reference_K,
)
    before=r7_pipe_inventory(s; cp_J_kgK, reference_K)
    all(isfinite, (mass_flow_kg_s, ambient_K, dt_h, UA_W_K))&&ambient_K>0&&dt_h>0&&UA_W_K>=0 ||
        error("流率、环境、步长或传热非法")
    m, q, M, D=Float64(mass_flow_kg_s),
    abs(Float64(mass_flow_kg_s)),
    before.mass_kg,
    3600Float64(dt_h)
    k=Float64(UA_W_K)/M/Float64(cp_J_kgK)
    moved=q*D
    all(isfinite, (D, k, moved)) || error("流量积分溢出")
    q>0 &&
        !(inlet_K isa Real&&isfinite(inlet_K)&&inlet_K>0) &&
        error("非零流量必须显式给出入口温度K")
    Ta=Float64(ambient_K)
    decay=exp(-k*D)
    lo, hi=m>=0 ? (max(0.0, M-moved), M) : (0.0, min(M, moved))
    kept_lo, kept_hi=m>=0 ? (0.0, max(0.0, M-moved)) : (min(M, moved), M)
    segments=r7_pipe_survivors(s, kept_lo, kept_hi, Ta, decay)
    out_old=q==0 ? 0.0 : r7_pipe_integral(s, lo, hi, Ta; exponent = x->-k*(m>0 ? M-x : x)/q)
    old_excess=r7_pipe_integral(s, 0.0, M, Ta)
    retained_excess=r7_pipe_integral(s, kept_lo, kept_hi, Ta)*decay
    # 每个旧水团只按其留管时间散热；不是用总能量平衡倒推损耗。
    loss_old=old_excess-retained_excess-out_old
    loss_new, out_new, input=0.0, 0.0, 0.0
    if q>0
        Tin=Float64(inlet_K)
        new=R7PipeSegment(min(moved, M), Ta, Tin-Ta, k/q, m>0)
        m>0 ? pushfirst!(segments, new) : push!(segments, new)
        transit=M/q
        out_new=max(0.0, moved-M)*(Tin-Ta)*exp(-k*transit)
        input=moved*(Tin-reference_K)
        b=min(D, transit)
        x=k*b
        # ∫(1-exp(-k*a)) da；小指数用级数避免相消。
        area=x<1e-4 ? b*(x/2-x^2/6+x^3/24-x^4/120+x^5/720) : b*(1+expm1(-x)/x)
        loss_new=q*(Tin-Ta)*(area+max(0.0, D-transit)*(-expm1(-k*transit)))
    end
    after_state=R7PipeState(segments)
    after=r7_pipe_inventory(after_state; cp_J_kgK, reference_K)
    output=out_old+out_new+moved*(Ta-reference_K)
    scale=Float64(cp_J_kgK)/3.6e9
    E_in, E_out, E_loss=scale*input, scale*output, scale*(loss_old+loss_new)
    balance=after.relative_heat_MWh-before.relative_heat_MWh-E_in+E_out+E_loss
    all(isfinite, (E_in, E_out, E_loss, balance)) || error("热输运结果溢出")
    (;
        state = after_state,
        outlet_mean_K = q==0 ? nothing : Ta+(out_old+out_new)/moved,
        before,
        after,
        input_heat_MWh = E_in,
        output_heat_MWh = E_out,
        loss_MWh = E_loss,
        energy_residual_MWh = balance,
        mass_residual_kg = after.mass_kg-M,
        version = "r7_plug_flow_reference_v1",
        normal_dispatch_verified = false,
    )
end
