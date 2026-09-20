# R7-F2：区间交集写成四个正部之差；界由全部实际有界流量推导，不用经验大M。
function r7_affine_interval(x)
    if x isa Real
        isfinite(x) || error("质量区间必须有有限界")
        return (Float64(x), Float64(x))
    elseif x isa VariableRef
        lo, hi=lower_bound(x), upper_bound(x)
        all(isfinite, (lo, hi)) || error("质量区间必须有有限界")
        return (lo, hi)
    end
    lo=hi=constant(x)
    for (a, v) in linear_terms(x)
        l, u=lower_bound(v), upper_bound(v)
        lo+=a*(a>=0 ? l : u)
        hi+=a*(a>=0 ? u : l)
    end
    all(isfinite, (lo, hi)) || error("正部线性化必须有有限变量界")
    lo, hi
end

function r7_positive_part!(m, x, tag)
    lo, hi=r7_affine_interval(x)
    hi<=0 && return 0.0
    lo>=0 && return x
    z=@variable(m, lower_bound=0, upper_bound=hi, base_name=tag)
    b=@variable(m, binary=true, base_name=tag*"_positive")
    @constraint(m, z>=x)
    @constraint(m, z<=hi*b)
    @constraint(m, z<=x-lo*(1-b))
    z
end

function r7_overlap!(m, a, b, c, d, tag)
    r7_positive_part!(m, b-c, tag*"_bc")-r7_positive_part!(m, a-c, tag*"_ac") -
    r7_positive_part!(m, b-d, tag*"_bd")+r7_positive_part!(m, a-d, tag*"_ad")
end

"""
    add_r7_mass_transport!(model, q, θ_in, θ_out, inventory, initial_mass, initial_θ;
                           prefix="pipe", deadline=Inf, allow_zero=false)

向JuMP加入R7-F2/F3无损正向塞流。q为每步通过质量/整管质量，θ为归一化温度；
inventory为相对温区下限的归一化整管显热，长度T+1。初始段按入口至出口排列且质量归一化和为1。
质量坐标交集随连续流量变化，分段正部精确线性化，温度与交集的乘积保留为二次等式。
不取整时延、不冻结输运权重；返回出口/库存交集以供独立证据保存，不求解或写文件。
显式allow_zero=true允许停流；此时出口温度无观测意义，库存继续受质量区间约束，重启继承原空间状态。
"""
function add_r7_mass_transport!(
    m,
    q,
    θ_in,
    θ_out,
    inventory,
    initial_mass,
    initial_θ;
    prefix = "pipe",
    deadline = Inf,
    allow_zero = false,
)
    T=length(q)
    length(θ_in)==length(θ_out)==T && length(inventory)==T+1 && T>0 || error("输运维度错误")
    length(initial_mass)==length(initial_θ)>0 &&
    all(>(0), initial_mass) &&
    all(isfinite, initial_mass) &&
    abs(sum(initial_mass)-1)<=1e-10 &&
    all(x->isfinite(x)&&0<=x<=1, initial_θ) || error("初始质量/温度错误")
    all(allow_zero ? first(r7_affine_interval(x))>=0 : first(r7_affine_interval(x))>0 for x in q) ||
        error("输运流量须符合声明的非负/严格正有限界")
    # ξ=-y为初始水团的入流标签；y从入口向出口。后续入口标签为累计正向质量。
    C=[sum(q[1:t]; init = 0.0) for t in 0:T]
    initial_edges=vcat(0.0, cumsum(initial_mass))
    source_lo=Any[-initial_edges[j+1] for j in eachindex(initial_mass)]
    source_hi=Any[-initial_edges[j] for j in eachindex(initial_mass)]
    append!(source_lo, C[1:(end-1)])
    append!(source_hi, C[2:end])
    temperatures=Any[initial_θ...; θ_in...]
    outlet_rows=Any[]
    inventory_rows=Any[]
    @constraint(m, inventory[1]==sum(initial_mass .* initial_θ))
    for t in 1:T
        time()<deadline || error("normal_flow_build_deadline")
        # 出口在[t-1,t]排出的标签[C[t-1]-1,C[t]-1]；末态保留[C[t]-1,C[t]]。
        idx=1:(length(initial_mass)+t)
        out=[
            r7_overlap!(m, C[t]-1, C[t+1]-1, source_lo[j], source_hi[j], "$(prefix)_o$(t)_$j") for
            j in idx
        ]
        inv=[
            r7_overlap!(m, C[t+1]-1, C[t+1], source_lo[j], source_hi[j], "$(prefix)_e$(t)_$j") for
            j in idx
        ]
        @constraint(m, q[t]*θ_out[t]==sum(out[j]*temperatures[j] for j in idx))
        @constraint(m, inventory[t+1]==sum(inv[j]*temperatures[j] for j in idx))
        push!(outlet_rows, out)
        push!(inventory_rows, inv)
    end
    (; cumulative = C, outlet_weights = outlet_rows, inventory_weights = inventory_rows)
end
