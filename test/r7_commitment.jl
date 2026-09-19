using Test, PaperRebuild, JuMP, HiGHS, TOML

@testset "R7 normal CHP prerequisites, not complete normal dispatch" begin
    root=normpath(joinpath(@__DIR__, ".."))
    data=TOML.parsefile(joinpath(root, "configs/r7/chp-component-hand.toml"))
    opt=optimizer_with_attributes(
        HiGHS.Optimizer,
        "threads"=>1,
        "primal_feasibility_tolerance"=>1e-9,
        "mip_feasibility_tolerance"=>1e-9,
        "mip_rel_gap"=>1e-9,
    )
    spec=R7CHPSpec(data)
    getvalues(b) = Dict(k=>Array(value.(v)) for (k, v) in b.variables)
    function optimize_block(d; fixed_u = nothing)
        m=Model(opt)
        b=add_r7_chp_commitment!(m, R7CHPSpec(d); fixed_u)
        @objective(m, Min, b.cost)
        set_silent(m)
        set_time_limit_sec(m, 10.0)
        optimize!(m)
        m, b
    end
    @testset "R7-N1 literal startup contradiction and zero-cost transitions" begin
        # 原6-6在启动当期要求ν=1<=1-u=0，单式已排除定义中的真正启动。
        literal=Model(opt)
        @variable(literal, u, Bin)
        @variable(literal, ν, Bin)
        fix(u, 1; force = true)
        fix(ν, 1; force = true)
        @constraint(literal, ν<=1-u)
        set_silent(literal)
        optimize!(literal)
        @test termination_status(literal)==MOI.INFEASIBLE
        d=deepcopy(data)
        d["startup_cost_USD"]=0.0
        m, b=optimize_block(d; fixed_u = [1, 1, 1, 0])
        @test termination_status(m)==MOI.OPTIMAL
        v=getvalues(b)
        @test v["ν_on"]≈[1, 0, 0, 0]
        @test v["ν_off"]≈[0, 0, 0, 1]
        @test validate_r7_chp(R7CHPSpec(d), v)["component_pass"]
        bad=deepcopy(v)
        bad["ν_on"][2]=bad["ν_off"][2]=1.0
        @test !validate_r7_chp(R7CHPSpec(d), bad)["component_pass"]
    end
    @testset "R7-N2 N3 N4 exhaustive dwell-time oracle" begin
        # 该判据直接检查每个相邻转换之间的持续小时数，不使用建模的滑动启停和式。
        function oracle(d, u)
            state=d["previous_commitment"]
            age=d["previous_duration_h"]
            for x in u
                if x!=state
                    age>=d[state==1 ? "min_on_h" : "min_off_h"] || return false
                    age=0.0
                end
                state=x
                age+=d["dt_h"]
            end
            d["terminal_rule"]=="carry_obligation" || age>=d[state==1 ? "min_on_h" : "min_off_h"]
        end
        for (initial, age, dt, on, off, tail) in (
            (0, 3.0, 1.0, 2.0, 1.0, "carry_obligation"),
            (1, 0.5, 1.0, 2.0, 1.0, "carry_obligation"),
            (0, 0.0, 0.5, 1.2, 0.75, "carry_obligation"),
            (1, 0.0, 0.5, 3.0, 1.0, "complete_within_horizon"),
            (0, 3.0, 1.0, 2.0, 1.0, "complete_within_horizon"),
            (1, 3.0, 1.0, 0.0, 0.0, "carry_obligation"),
        )
            d=deepcopy(data)
            merge!(
                d,
                Dict(
                    "previous_commitment"=>initial,
                    "previous_duration_h"=>age,
                    "dt_h"=>dt,
                    "min_on_h"=>on,
                    "min_off_h"=>off,
                    "terminal_rule"=>tail,
                    "P_min_MW"=>0.0,
                    "previous_P_MW"=>[0.0, 0.0],
                ),
            )
            s=R7CHPSpec(d)
            for mask in 0:15
                u=[(mask>>(t-1))&1 for t in 1:4]
                expected=oracle(d, u)
                m, b=optimize_block(d; fixed_u = u)
                @test termination_status(m)==(expected ? MOI.OPTIMAL : MOI.INFEASIBLE)
                expected && @test validate_r7_chp(s, getvalues(b))["component_pass"]
                @test b.component_class=="LP"
            end
        end
        d=deepcopy(data)
        m, b=optimize_block(d; fixed_u = [0, 0, 0, 1])
        @test termination_status(m)==MOI.OPTIMAL
        check=validate_r7_chp(R7CHPSpec(d), getvalues(b))
        @test check["terminal_state"]==1 && check["terminal_remaining_h"]==1.0
        d["terminal_rule"]="complete_within_horizon"
        m, _=optimize_block(d; fixed_u = [0, 0, 0, 1])
        @test termination_status(m)==MOI.INFEASIBLE
    end
    @testset "R7-N5 cost, stochastic sharing, ramping and units" begin
        # 冻结合成单设备负荷，不含电热网络；总费可手算为30+20*(.25*2+.75*1.8)=67。
        demand=[0.5 0.6; 1.0 0.8; 0.5 0.4; 0.0 0.0]
        m=Model(opt)
        b=add_r7_chp_commitment!(m, spec)
        @variable(m, 0<=grid[1:4, 1:2]<=2)
        @constraint(m, [t=1:4, w=1:2], grid[t, w]+b.variables["P_CHP"][t, w]==demand[t, w])
        @objective(
            m,
            Min,
            b.cost+100sum(data["probabilities"][w]*grid[t, w] for t in 1:4, w in 1:2)
        )
        set_silent(m)
        optimize!(m)
        @test termination_status(m)==MOI.OPTIMAL
        @test objective_value(m)≈67.0 atol=1e-7
        @test objective_bound(m)≈67.0 atol=1e-7
        @test b.component_class=="MILP"
        @test all(F in (VariableRef, AffExpr) for (F, _) in list_of_constraint_types(m))
        v=getvalues(b)
        @test v["u_CHP"]≈[1, 1, 1, 0]
        @test v["P_CHP"]≈demand atol=1e-7
        verified=validate_r7_chp(spec, v)
        @test verified["component_pass"]
        @test verified["startup_cost_USD"]≈30
        @test verified["running_cost_USD"]≈37
        @test !verified["normal_network_verified"] && !verified["preplan_optimality_verified"]
        half=deepcopy(data)
        merge!(half, Dict("dt_h"=>0.5, "min_on_h"=>1.0, "min_off_h"=>0.5, "ramp_MW_h"=>1.0))
        hc=validate_r7_chp(R7CHPSpec(half), v)
        @test hc["component_pass"] && hc["total_cost_USD"]≈48.5
        rampbad=deepcopy(v)
        rampbad["P_CHP"][1, 1]=0.7
        rampbad["H_CHP"][1, 1]=0.7
        @test !validate_r7_chp(spec, rampbad)["component_pass"]
        qbad=deepcopy(v)
        qbad["Q_CHP"][4, 2]=0.1
        @test !validate_r7_chp(spec, qbad)["component_pass"]
        @testset "R7-N6 inherited CHP event boundary" begin
            ev=r7_chp_event_boundary(spec, v; event_start = 3, periods = 2)
            @test ev["fields"]["commitment"]==[1, 0]
            @test ev["fields"]["previous_P_MW"]≈[1.0, 0.8]
            @test ev["fields"]["previous_commitment"]==1
            @test ev["scope"]=="chp_component_only" && !ev["preplan_optimality_verified"]
            first=r7_chp_event_boundary(spec, v; event_start = 1, periods = 1)
            @test first["fields"]["previous_P_MW"]==[0.0, 0.0]
            @test first["fields"]["previous_commitment"]==0
            @test_throws ErrorException r7_chp_event_boundary(spec, v; event_start = 4, periods = 2)
            @test_throws ErrorException r7_chp_event_boundary(
                spec,
                rampbad;
                event_start = 1,
                periods = 1,
            )
            alternate=deepcopy(v)
            alternate["Q_CHP"][1, 1]=0.1
            @test r7_chp_event_boundary(spec, alternate; event_start = 3, periods = 2)["values_sha256"]!=ev["values_sha256"]
        end
        malformed=deepcopy(v)
        malformed["P_CHP"][1, 1]=NaN
        @test_throws ErrorException validate_r7_chp(spec, malformed)
    end
    @testset "R7-N7 nonlinear normal heat is not justified by compact MILP" begin
        # 两个满足同一H=c*m*DeltaT的状态，中点不满足，证明该等式图非凸。
        c=4200/1e6
        @test c*1*40≈c*2*20≈0.168
        @test c*1.5*30-0.168≈0.021
        @test (1.0^2+3.0^2)/2-((1.0+3.0)/2)^2==1
        # 不能将恢复期Taylor约束当正常热网的等价式。
        @test c*(2-1)*(40-20)≈0.084
    end
    @testset "R7 input boundaries and no source mutation" begin
        for (k, x) in (
            ("dt_h", 0.0),
            ("previous_duration_h", -1.0),
            ("P_min_MW", 2.0),
            ("terminal_rule", "implicit"),
            ("probabilities", [0.5, 0.6]),
            ("previous_P_MW", [0.2, 0.0]),
            ("cost_basis", "add_unspecified_heat_cost"),
        )
            d=deepcopy(data)
            d[k]=x
            @test_throws ErrorException R7CHPSpec(d)
        end
        mutable_spec=R7CHPSpec(data)
        mutable_spec.data["P_max_MW"]=2.0
        @test_throws ErrorException add_r7_chp_commitment!(Model(), mutable_spec)
        @test_throws ErrorException add_r7_chp_commitment!(Model(), spec; fixed_u = [0.5, 1, 1, 0])
        m=Model()
        add_r7_chp_commitment!(m, spec)
        second=deepcopy(data)
        second["id"]="CHP2"
        @test add_r7_chp_commitment!(m, R7CHPSpec(second)).component_class=="MILP"
    end
end
