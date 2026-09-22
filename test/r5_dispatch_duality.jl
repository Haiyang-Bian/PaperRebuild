module R5DispatchDualityTests
using PaperRebuild, JuMP, HiGHS, Clarabel, Test, TOML
const RD=PaperRebuild
include(joinpath(@__DIR__, "..", "scripts", "r5_dispatch_cases.jl"))
highs=optimizer_with_attributes(
    HiGHS.Optimizer,
    "primal_feasibility_tolerance"=>1e-9,
    "dual_feasibility_tolerance"=>1e-9,
)
clarabel=optimizer_with_attributes(
    Clarabel.Optimizer,
    "tol_feas"=>1e-10,
    "tol_gap_abs"=>1e-10,
    "tol_gap_rel"=>1e-10,
)

function smooth_case(; elastic = false, dt = 1.0)
    d=r5_dispatch_hand(; dt)
    d["devices"][2]["p_max_MW"]=0.2
    d["devices"][2]["P_initial_MW"]=0.05
    d["devices"][2]["cost_USD_MWh"]=elastic ? 2000.0 : 130.0
    a=d["award"]
    rt=d["realtime"]
    a["P_DA_MW"]=[elastic ? 0.142 : 0.112]
    a["R_up_MW"]=[elastic ? 0.1 : 0.02]
    a["R_down_MW"]=[elastic ? 0.0 : 0.02]
    rt["alpha_up"]=[0.4]
    rt["alpha_down"]=[elastic ? 0.0 : 0.2]
    rt["price"]=[80.0]
    rt["delta"]=elastic ? 0.1 : 0.0
    R5DispatchCase(d)
end

@testset "R5 recourse independent coefficient inventory" begin
    for d in (r5_dispatch_hand(), r5_dispatch_teaching())
        c=R5DispatchCase(d)
        b=build_r5_dispatch(c)
        sys=RD.r5_dispatch_dual_system(c)
        @test Set(keys(b.rows))==Set(k for (k, z) in sys.rows if !z.bound)
        coefficients_ok=true
        for (id, ref) in b.rows
            row=sys.rows[id]
            coefficients_ok &= isapprox(JuMP.normalized_rhs(ref), row.rhs; atol = 1e-10)
            sense=JuMP.constraint_object(ref).set
            coefficients_ok &=
                row.sense==(sense isa MOI.EqualTo ? :eq : sense isa MOI.LessThan ? :le : :ge)
            for (key, vars) in pairs(b.variables), idx in CartesianIndices(vars)
                k="$key/$(idx[1])/$(idx[2])"
                coefficients_ok &= isapprox(
                    JuMP.normalized_coefficient(ref, vars[idx]),
                    get(row.coefficients, k, 0.0);
                    atol = 1e-10,
                )
            end
        end
        @test coefficients_ok
        @test JuMP.constant(JuMP.objective_function(b.model))≈sys.constant
    end
end

@testset "R5 recourse KKT and independent dual" begin
    for optimizer in (highs, clarabel),
        c in (
            R5DispatchCase(r5_dispatch_hand()),
            R5DispatchCase(r5_dispatch_teaching()),
            smooth_case(),
            smooth_case(; elastic = true),
        )

        r=solve_r5_dispatch(c; optimizer)
        cert=validate_r5_dispatch_duals(c, r)
        !cert["kkt_pass"]&&println(
            "KKT failure: ",
            get(cert, "status", ""),
            " ",
            [x for x in cert["rows"] if !x["pass"]],
        )
        @test cert["model_pass"]
        @test cert["kkt_pass"]
        b=build_r5_dispatch_dual(c; optimizer)
        @test termination_status(b.model)==MOI.OPTIMIZE_NOT_CALLED
        set_silent(b.model)
        set_time_limit_sec(b.model, 60)
        optimize!(b.model)
        @test termination_status(b.model)==MOI.OPTIMAL
        @test isapprox(objective_value(b.model), r["solver_objective"]; atol = 1e-5, rtol = 1e-6)
        @test cert["relative_gap"]<=1e-4
    end
end

@testset "R5 recourse sensitivity analytic and finite differences" begin
    for optimizer in (highs, clarabel), elastic in (false, true), dt in (1.0, 0.25)
        c=smooth_case(; elastic, dt)
        r=solve_r5_dispatch(c; optimizer)
        s=r5_dispatch_sensitivity(c, r; objective = :total)
        @test s["trusted"]
        expected=elastic ? Dict("P_DA_MW"=>-1900.0, "R_up_MW"=>671.0) :
                 Dict("P_DA_MW"=>-30.0, "R_up_MW"=>15.0, "R_down_MW"=>-12.0)
        for (key, value) in expected
            @test isapprox(s["gradient"][key][1], dt*value; atol = 1e-4, rtol = 1e-6)
            for step in (1e-3, 1e-4, 1e-5)
                pair=Float64[]
                for sign in (-1, 1)
                    d=deepcopy(c.data)
                    d["award"][key][1]+=sign*step
                    result=solve_r5_dispatch(R5DispatchCase(d); optimizer)
                    @test result["validation"]["model_pass"]
                    push!(pair, result["solver_objective"])
                end
                difference=(pair[2]-pair[1])/(2step)
                @test abs(difference-s["gradient"][key][1])/max(
                    1,
                    abs(difference),
                    abs(s["gradient"][key][1]),
                )<=1e-3
            end
        end
        if elastic
            @test isapprox(r["validation"]["mismatch_MWh"], dt*0.01; atol = 1e-7)
            @test isapprox(s["contributions"]["capacity_budget"][1], -dt*92; atol = 1e-4)
        end
        rec=r5_dispatch_sensitivity(c, r)
        @test rec["trusted"]
        @test isapprox(rec["value"]+r["validation"]["day_ahead_cost"], s["value"]; atol = 1e-9)
        @test rec["gradient"]["P_DA_MW"][1]+dt*c.data["award"]["energy_price"][1]≈s["gradient"]["P_DA_MW"][1]
    end
end

@testset "R5 recourse scaling and nonsmooth subgradient" begin
    c=smooth_case(; elastic = true)
    r=solve_r5_dispatch(c; optimizer = highs)
    s=r5_dispatch_sensitivity(c, r; objective = :total)
    scaled=deepcopy(c.data)
    for key in ("energy_price", "up_price", "down_price")
        scaled["award"][key].*=3
    end
    scaled["realtime"]["price"].*=3
    scaled["realtime"]["penalty_USD_MWh"]*=3
    for dev in scaled["devices"]
        dev["cost_USD_MWh"]*=3
    end
    cc=R5DispatchCase(scaled)
    rr=solve_r5_dispatch(cc; optimizer = highs)
    ss=r5_dispatch_sensitivity(cc, rr; objective = :total)
    @test ss["trusted"]
    @test ss["value"]≈3s["value"]
    @test all(
        isapprox(ss["gradient"][k], 3s["gradient"][k]; atol = 1e-6) for k in keys(s["gradient"])
    )
    d=r5_dispatch_hand()
    d["award"]["R_up_MW"]=[0.1]
    d["realtime"]["delta"]=1.0
    d["realtime"]["price"]=[80.0]
    for optimizer in (highs, clarabel)
        c=R5DispatchCase(d)
        r=solve_r5_dispatch(c; optimizer)
        s=r5_dispatch_sensitivity(c, r; objective = :total)
        @test s["trusted"]
        g=s["gradient"]["P_DA_MW"][1]
        @test -980-1e-5<=g<=1020+1e-5
        for h in (1e-3, 1e-4, 1e-5), sign in (-1, 1)
            shifted=deepcopy(d)
            shifted["award"]["P_DA_MW"][1]+=sign*h
            trial=solve_r5_dispatch(R5DispatchCase(shifted); optimizer)
            @test trial["validation"]["model_pass"]
            @test trial["solver_objective"]>=s["value"]+g*sign*h-1e-6
        end
    end
end

@testset "R5 recourse missing and corrupt duals" begin
    c=smooth_case()
    r=solve_r5_dispatch(c; optimizer = highs)
    for kind in (:missing, :inventory, :sign, :stationarity, :nan, :primal)
        x=deepcopy(r)
        if kind==:missing
            delete!(x, "raw_bound_duals")
        elseif kind==:inventory
            delete!(x["raw_constraint_duals"], "5-4/window/0")
        elseif kind==:sign
            x["raw_bound_duals"]["P_DER/2/1/upper"]=1e6
        elseif kind==:stationarity
            x["raw_constraint_duals"]["R5-D-delivery/PCC/1"]+=100
        elseif kind==:nan
            x["raw_constraint_duals"]["5-4/window/0"]=NaN
        else
            x["values"]["τ_IN"][1][1]+=1
        end
        k=validate_r5_dispatch_duals(c, x)
        @test !k["kkt_pass"]
        s=r5_dispatch_sensitivity(c, x)
        @test !s["trusted"]&&isempty(s["gradient"])
    end
    @test_throws ErrorException r5_dispatch_sensitivity(c, r; objective = :wrong)
    # 旧运行通过只读补证；不改写历史validation、源哈希或旧状态。
    old=joinpath(
        @__DIR__,
        "..",
        "results",
        "runs",
        "r5",
        "r5-dispatch-20260919",
        "four_period--highs",
    )
    if isdir(old)
        x=read_r5_dispatch_run(old)
        before=RD.r5_market_text(x.result)
        @test validate_r5_dispatch_duals(x.case, x.result)["kkt_pass"]
        @test RD.r5_market_text(x.result)==before
    end
end
end
