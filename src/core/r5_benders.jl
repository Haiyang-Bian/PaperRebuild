const R5_BENDERS_CORE_FILE = @__FILE__

"""
    R5BendersSpec(; feasibility=:cuts, critical_count=1, max_iterations=200,
                  absolute_gap=1e-7, relative_gap=1e-6,
                  cut_arithmetic=:float_box, diagnostic_scale=1.0)

第5章有限支持条件Benders规则。cuts使用弹性可行性割，critical插入关键情景完整物理约束。
paper_critical另实施原(5-102)的外集z=0；其受限域界不作为完整风险模型的全局下界。
间隙规则是预先声明的项目数值设置，不冒称作者给出了同一σ；不改变A1/A2/KKT。
float_box保留原浮点保护模式；rational_box对已编码的有限盒LP计算有理数误差界。
diagnostic_scale指定u=scale*y的二次幂表示；外层默认显式采用rational_box和1024倍诊断表示。
"""
struct R5BendersSpec
    feasibility::Symbol
    critical_count::Int
    max_iterations::Int
    absolute_gap::Float64
    relative_gap::Float64
    cut_arithmetic::Symbol
    diagnostic_scale::Float64
    function R5BendersSpec(;
        feasibility = :cuts,
        critical_count = 1,
        max_iterations = 200,
        absolute_gap = 1e-7,
        relative_gap = 1e-6,
        cut_arithmetic = :float_box,
        diagnostic_scale = 1.0,
    )
        feasibility in (:cuts, :critical, :paper_critical) || error("未知Benders可行性路线")
        critical_count isa Integer && critical_count>0 || error("关键情景个数必须为正整数")
        max_iterations isa Integer && 1<=max_iterations<=200 || error("外层次数必须为1至200")
        all(isfinite, (absolute_gap, relative_gap)) && absolute_gap>=0 && 0<=relative_gap<=1e-4 ||
            error("分解间隙规则非法")
        cut_arithmetic in (:float_box, :rational_box)||error("未知割算术模式")
        r5_benders_check_scale(diagnostic_scale)
        new(
            feasibility,
            critical_count,
            max_iterations,
            absolute_gap,
            relative_gap,
            cut_arithmetic,
            diagnostic_scale,
        )
    end
end
r5_benders_spec(s::R5BendersSpec) = Dict(
    "feasibility"=>string(s.feasibility),
    "critical_count"=>s.critical_count,
    "max_iterations"=>s.max_iterations,
    "absolute_gap"=>s.absolute_gap,
    "relative_gap"=>s.relative_gap,
    "cut_arithmetic"=>string(s.cut_arithmetic),
    "diagnostic_scale"=>s.diagnostic_scale,
)
r5_benders_spec(d::AbstractDict) = R5BendersSpec(;
    feasibility = Symbol(d["feasibility"]),
    critical_count = d["critical_count"],
    max_iterations = d["max_iterations"],
    absolute_gap = d["absolute_gap"],
    relative_gap = d["relative_gap"],
    cut_arithmetic = Symbol(get(d, "cut_arithmetic", "float_box")),
    diagnostic_scale = get(d, "diagnostic_scale", 1.0),
)

function r5_benders_check_scale(scale)
    isfinite(scale)&&1<=scale<=2.0^20&&isinteger(log2(scale))||error("数值缩放须为1至2^20的二次幂")
    Float64(scale)
end

r5_benders_rational(x) = Rational{BigInt}(Float64(x))
function r5_benders_outward(x, side)
    f=Float64(x)
    isfinite(f)||error("有限盒或割发生浮点溢出")
    side==:down ? (r5_benders_rational(f)>x ? prevfloat(f) : f) :
    (r5_benders_rational(f)<x ? nextfloat(f) : f)
end
function r5_benders_exact_range(a, box; constant = 0.0)
    lo=hi=r5_benders_rational(constant)
    for (k, v) in a
        l, u=r5_benders_rational.(box[k])
        q=r5_benders_rational(v)
        lo+=min(q*l, q*u)
        hi+=max(q*l, q*u)
    end
    lo, hi
end

function r5_benders_xbox(c)
    Dict(
        "$k/$t"=>(Float64(b["lower"][t]), Float64(b["upper"][t])) for
        (k, b) in c.data["commitment"]["bounds"] for t in eachindex(b["lower"])
    )
end
r5_benders_flat(x) =
    Dict("$k/$t"=>Float64(x[k][t]) for k in R5_COMMITMENT_KEYS for t in eachindex(x[k]))
function r5_benders_xcheck(c, x)
    T=first(c.data["commitment"]["scenarios"])["case"]["T"]
    Set(keys(x))==Set(R5_COMMITMENT_KEYS) && all(
        x[k] isa AbstractVector && length(x[k])==T && all(isfinite, x[k]) for
        k in R5_COMMITMENT_KEYS
    ) || error("Benders承诺维度或数值错误")
    x
end
function r5_benders_range(a, box; constant = 0.0)
    lo, hi=Float64(constant), Float64(constant)
    for (k, v) in a
        l, u=box[k]
        lo+=min(v*l, v*u)
        hi+=max(v*l, v*u)
    end
    (lo, hi)
end
function r5_benders_view(c, scenario, x, branch)
    branch in (0, 1) || error("舒适分支必须为0或1")
    base=branch==0 ? R5CommitmentCase(c.data["commitment"]) : r5_risk_physical_case(c)
    1<=scenario<=length(base.data["scenarios"]) || error("情景索引越界")
    r5_commitment_view(base, base.data["scenarios"][scenario], r5_benders_xcheck(c, x))
end

# b(x)=b0+B*x；只在原交付、误差双行及容量分母预算中出现共同承诺。
function r5_benders_rhs(view, id, row)
    parts=split(id, '/')
    rt=view.data["realtime"]
    B=Dict{String,Float64}()
    b0=row.rhs
    if parts[1]=="R5-D-delivery"
        B["P_DA_MW/$(parts[3])"]=1.0
        b0=0.0
    elseif parts[1] in ("5-3-plus", "5-3-minus")
        t=parse(Int, parts[3])
        sign=parts[1]=="5-3-plus" ? 1.0 : -1.0
        B["R_up_MW/$t"]=sign*rt["alpha_up"][t]
        B["R_down_MW/$t"]=-sign*rt["alpha_down"][t]
        b0=0.0
    elseif parts[1]=="5-4"
        for k in ("R_up_MW", "R_down_MW"), t in 1:view.data["T"]
            B["$k/$t"]=rt["delta"]*view.data["dt_h"]
        end
        b0=0.0
    end
    (; constant = Float64(b0), coefficients = B)
end

"""
    r5_benders_bounds(case, scenario)

由第5章设备/节点边界、交付等式、累计误差和固定流量输运推导有限补救盒及净费用下界。
交付界为P日前盒减PCC盒；误差上界来自(5-4)，热量界来自(5-19)，管出口温度由线性输运区间推出。
所有界对完整日前盒和两种舒适分支有效，允许负补救费用；不求解、不使用参考解。
"""
function r5_benders_bounds(c::R5RiskCase, scenario::Integer)
    r5_risk_assert_case(c)
    x=Dict(k=>copy(c.data["commitment"]["bounds"][k]["lower"]) for k in R5_COMMITMENT_KEYS)
    view=r5_benders_view(c, scenario, x, 1)
    sys=r5_dispatch_dual_system(view)
    box=Dict(k=>(-Inf, Inf) for k in keys(sys.cost))
    xb=r5_benders_xbox(c)
    for row in values(sys.rows)
        row.bound || continue
        k, v=only(row.coefficients)
        v==1.0 || error("未支持的补救界形式")
        lo, hi=box[k]
        box[k]=row.sense==:ge ? (max(lo, row.rhs), hi) : (lo, min(hi, row.rhs))
    end
    d=view.data
    e=d["electric"]
    h=d["heat"]
    ratio=r5_benders_rational(d["realtime"]["delta"]*d["dt_h"])/r5_benders_rational(d["dt_h"])
    mismatch=r5_benders_outward(
        ratio*sum(
            r5_benders_rational(xb["$k/$t"][2]) for k in ("R_up_MW", "R_down_MW") for t in 1:d["T"]
        ),
        :up,
    )
    for t in 1:d["T"]
        box["delivery/1/$t"]=(
            r5_benders_outward(
                r5_benders_rational(xb["P_DA_MW/$t"][1])-r5_benders_rational(e["pcc_max_MW"]),
                :down,
            ),
            r5_benders_outward(
                r5_benders_rational(xb["P_DA_MW/$t"][2])-r5_benders_rational(e["pcc_min_MW"]),
                :up,
            ),
        )
        box["mismatch/1/$t"]=(0.0, mismatch)
        for (j, b) in enumerate(d["buildings"])
            key="H_D/$j/$t"
            row=sys.rows["5-19/$(b["id"])/$t"]
            _, hi=r5_benders_exact_range(
                Dict(k=>-a for (k, a) in row.coefficients if k!=key),
                box;
                constant = row.rhs,
            )
            box[key]=(0.0, max(0.0, r5_benders_outward(hi, :up)))
        end
        for (p, pipe) in enumerate(h["pipes"]), side in ("S", "R")
            key="τ_pipe_$side/$p/$t"
            row=sys.rows["5-25-26-$side/$(pipe["id"])/$t"]
            terms=Dict(k=>-a for (k, a) in row.coefficients if k!=key)
            lr, hr=r5_benders_exact_range(terms, box; constant = row.rhs)
            lo, hi=r5_benders_outward(lr, :down), r5_benders_outward(hr, :up)
            pad=1e-12*max(1.0, abs(lo), abs(hi))
            box[key]=(lo-pad, hi+pad)
        end
    end
    all(isfinite(l)&&isfinite(u)&&l<=u for (l, u) in values(box)) || error("未取得完整有效补救盒")
    lr, hr=r5_benders_exact_range(sys.cost, box)
    lo, hi=r5_benders_outward(lr, :down), r5_benders_outward(hr, :up)
    margin=1e-10*max(1.0, abs(lo), abs(hi))
    (;
        box,
        first_stage_box = xb,
        lower_cost = lo-margin,
        upper_cost = hi+margin,
        provenance = "input_bounds_delivery_budget_heat_and_transport_intervals",
    )
end

function r5_benders_system(c, scenario, x, branch; elastic = false)
    view=r5_benders_view(c, scenario, x, branch)
    old=r5_dispatch_dual_system(view)
    bounds=r5_benders_bounds(c, scenario)
    box=copy(bounds.box)
    rows=Dict{String,Any}()
    cost=copy(old.cost)
    for (id, row) in old.rows
        rhs=r5_benders_rhs(view, id, row)
        rows[id]=(;
            coefficients = copy(row.coefficients),
            sense = row.sense,
            rhs = rhs.constant,
            parameters = rhs.coefficients,
            bound = row.bound,
        )
    end
    # 原本无显式上界的变量加上已证明有效的盒；同时保留原舒适分支的更紧界。
    for (k, (lo, hi)) in bounds.box, (side, sense, rhs) in (("lower", :ge, lo), ("upper", :le, hi))
        id="$k/$side"
        if !haskey(rows, id)
            rows[id]=(;
                coefficients = Dict(k=>1.0),
                sense,
                rhs,
                parameters = Dict{String,Float64}(),
                bound = true,
            )
        end
    end
    scales=Dict{String,Float64}()
    if elastic
        cost=Dict(k=>0.0 for k in keys(old.cost))
        # 舒适界属于诊断关系；物理域盒保持硬约束，z不放松最终设备/网络。
        for (j, b) in enumerate(view.data["buildings"]),
            t in 1:view.data["T"],
            side in ("lower", "upper")

            id="τ_IN/$j/$t/$side"
            row=rows[id]
            rows[id]=merge(row, (bound = false,))
        end
        for (id, row) in collect(rows)
            row.bound && continue
            lhs=r5_benders_range(row.coefficients, bounds.box)
            rhs=r5_benders_range(row.parameters, bounds.first_stage_box; constant = row.rhs)
            M=max(1.0, abs(lhs[1]-rhs[2]), abs(lhs[2]-rhs[1]))
            scales[id]=M
            coeff=copy(row.coefficients)
            signs=row.sense==:eq ? (1.0, -1.0) : (row.sense==:ge ? (1.0,) : (-1.0,))
            for (j, sign) in enumerate(signs)
                k="elastic/$id/$j"
                coeff[k]=sign
                cost[k]=1/M
                box[k]=(0.0, M+1e-9*M)
            end
            rows[id]=merge(row, (coefficients = coeff,))
        end
        # 诊断采用统一物理域，保证任何日前盒点都有有界弹性解。
        for (k, (lo, hi)) in box, (side, sense, rhs) in (("lower", :ge, lo), ("upper", :le, hi))
            id="R5-B-box/$k/$side"
            rows[id]=(;
                coefficients = Dict(k=>1.0),
                sense,
                rhs,
                parameters = Dict{String,Float64}(),
                bound = true,
            )
        end
    end
    variable_scales=Dict(
        k=>get(old.scales, k, max(1.0, abs(box[k][1]), abs(box[k][2]))) for k in keys(cost)
    )
    (;
        view,
        rows,
        cost,
        box,
        xb = bounds.first_stage_box,
        sizes = old.sizes,
        variable_scales,
        money_scale = elastic ? 1.0 : old.money_scale,
        elastic,
        scales,
        bounds,
    )
end

function r5_benders_rhs_value(row, x)
    row.rhs+sum(a*x[k] for (k, a) in row.parameters; init = 0.0)
end

function r5_benders_science_hashes()
    Dict(rel=>bytes2hex(sha256(read(path))) for (rel, path) in r5_benders_science_paths())
end

function r5_benders_critical(c, spec, critical)
    ids=Int.(critical)
    length(unique(ids))==length(ids)&&all(
        1<=s<=length(c.data["commitment"]["scenarios"]) for s in ids
    )||error("关键情景索引错误")
    spec.feasibility==:cuts&&!isempty(ids)&&error("纯割路线不插入关键情景")
    sort(ids)
end
r5_benders_scope(c, spec, critical) =
    spec.feasibility==:paper_critical&&length(critical)<length(c.data["commitment"]["scenarios"]) ?
    "restricted_comfort_domain" : "full_risk_domain"
r5_benders_dot(a, x) = sum(v*x[k] for (k, v) in a; init = 0.0)
r5_benders_affine(cut, x) = cut["constant"]+r5_benders_dot(cut["gradient"], x)
function r5_benders_cut_key(cut)
    fields=("kind", "scenario", "branch", "constant", "gradient", "deactivation_M", "lower_cost")
    bytes2hex(sha256(r5_market_text(Dict(k=>cut[k] for k in fields))))
end

function r5_benders_gap(upper, lower, spec)
    valid=isfinite(upper)&&isfinite(lower)&&lower<=upper+1e-6*max(1, abs(upper))
    absolute=valid ? max(0.0, upper-lower) : Inf
    relative=valid ? absolute/max(1.0, abs(upper), abs(lower)) : Inf
    Dict(
        "valid"=>valid,
        "absolute"=>absolute,
        "relative"=>relative,
        "stopping_pass"=>valid&&absolute<=spec.absolute_gap+spec.relative_gap*max(
            1.0,
            abs(upper),
            abs(lower),
        ),
        "a2_pass"=>valid&&relative<=1e-4,
    )
end
