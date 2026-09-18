using Test, PaperRebuild, JuMP, Clarabel

function r4_thermal_handcase(; idle = false)
    old=load_r4_case(joinpath(@__DIR__, "..", "configs", "r4", "reconfiguration", "oracle.toml"))
    d=deepcopy(old.data)
    d["name"]=idle ? "thermal_idle_handcase" : "thermal_pair_handcase"
    d["admission_policy"]="unrestricted"
    d["description"]="合成解析测试：1kg/s、恒负荷，明确闲置叶支路，不是正式研究输入。"
    for a in d["actors"]
        for key in
            ("CHP_max", "HP_max", "EB_max", "PV_max", "BS_power_max", "BS_energy_max", "BS_initial")
            a[key]=0.0
        end
        a["flex"]=0.0
        a["H_load"]=[0.0]
        a["H_preferred"]=[0.0]
        a["P_load"]=[0.1]
        a["P_preferred"]=[0.1]
    end
    d["actors"][idle ? 2 : 1]["EB_max"]=1.0
    d["actors"][1]["P_load"]=[0.0]
    d["actors"][1]["P_preferred"]=[0.0]
    d["actors"][3]["H_load"]=[0.16468]
    d["actors"][3]["H_preferred"]=[0.16468]
    mass=Dict(
        "m_pipe"=>reshape(idle ? [0.0, 1, 0, 0, 0, 0] : [1.0, 1, 0, 0, 0, 0], :, 1),
        "m_source"=>reshape(idle ? [0.0, 1, 0] : [1.0, 0, 0], :, 1),
        "m_load"=>reshape([0.0, 0, 1], :, 1),
    )
    options=(;
        modes = [0],
        electric_schedule = reshape([1, 1, 0], :, 1),
        heat_open = [1, 1, 0],
        mass_schedule = mass,
    )
    R4Case(d), options
end

@testset "R4-T1 R4-T2 R4-T3 R4-T4 R4-T5 R4-T6 steady thermal dispatch" begin
    z=r4_steady_pipe(353.15, 283.15, 1.0, 18.0)
    @test z.outlet_K≈283.15+70exp(-18/4180)
    @test z.loss_MW≈0.00418*(353.15-z.outlet_K)
    @test r4_steady_pipe(353.15, 283.15, 1.0, 0.0).loss_MW==0
    @test r4_steady_pipe(353.15, 283.15, 1e10, 18.0).loss_MW≈0.00126 rtol=1e-10
    @test r4_steady_pipe(353.15, 283.15, 1.0, 1e8).outlet_K==283.15
    @test r4_steady_pipe(353.15, 283.15, 2.0, 36.0).outlet_K==z.outlet_K
    @test_throws ErrorException r4_steady_pipe(353.15, 283.15, 0.0, 18.0)
    @test_throws ErrorException r4_steady_pipe(353.15, 283.15, -1.0, 18.0)
    @test_throws ErrorException r4_steady_pipe(NaN, 283.15, 1.0, 18.0)
    @test_throws ErrorException R4ThermalSpec(loss = :zero)
    @test_throws ErrorException R4ThermalSpec(flow_floor = 0)
    @test_throws ErrorException R4ThermalSpec(return_K = (340.0, 350.0))
    c, options=r4_thermal_handcase()
    ref=R4ThermalSpec(electric = :socp, loss = :reference, policy = :fixed)
    exp_spec=R4ThermalSpec(electric = :socp, loss = :exponential, policy = :fixed)
    @test PaperRebuild.r4_thermal_spec(PaperRebuild.r4_thermal_spec(ref))==ref
    @test r4_thermal_min_flow(c, ref)[1]≈0.00126/(0.00418*20)
    mmin=r4_thermal_min_flow(c, exp_spec)[1]
    @test r4_steady_pipe(exp_spec.supply_K[2], 283.15, mmin, 18.0).outlet_K≈exp_spec.supply_K[1]
    @test_throws ErrorException R4ThermalSpec(supply_K = (NaN, 363.0))
    bad=deepcopy(options.mass_schedule)
    bad["m_pipe"][1, 1]=2.0
    @test_throws ErrorException build_r4_thermal(c; mass_schedule = bad)
    @test_throws ErrorException build_r4_thermal(c; options..., heat_active = zeros(Int, 6, 1))
    opt=optimizer_with_attributes(Clarabel.Optimizer, "tol_feas"=>1e-10, "tol_gap_abs"=>1e-10)
    for idle in (false, true), spec in (ref, exp_spec)
        cc, opts=r4_thermal_handcase(; idle)
        b=build_r4_thermal(cc; spec, opts...)
        @test b.model_class=="SOCP"
        @test !any(
            F<:JuMP.GenericNonlinearExpr || F<:JuMP.GenericQuadExpr for
            (F, S) in list_of_constraint_types(b.model)
        )
        r=solve_r4_thermal(cc; spec, optimizer = opt, opts..., budget_sec = 60)
        @test haskey(r, "values")
        @test r["validation"]["model_pass"]
        @test r["validation"]["electric_original_pass"]
        if haskey(r, "values")
            if spec.loss==:reference
                @test r["values"]["H_src"][idle ? 2 : 1][1]≈0.16468+(idle ? 1 : 2)*0.0018 atol=3e-7
            end
            if idle
                @test abs(r["values"]["H_in"][1][1])<1e-8
                @test r["values"]["u_H"][1]≈1
                @test abs(r["values"]["u_H_arc"][1][1])<1e-8
            end
            bad=deepcopy(r)
            bad["values"]["τ_S_out"][2][1]+=0.1
            @test !validate_r4_thermal(cc, bad)["model_pass"]
            bad=deepcopy(r)
            bad["thermal"]["loss"]="other"
            @test_throws ErrorException validate_r4_thermal(cc, bad)
            mktempdir() do dir
                path=save_r4_run(cc, r; directory = dir, run_id = "thermal")
                @test read_r4_run(path).validation==r["validation"]
                @test_throws ErrorException save_r4_run(cc, r; directory = dir, run_id = "thermal")
                open(joinpath(path, "result.toml"), "a") do io
                    write(io, "\n# changed\n")
                end
                @test_throws ErrorException read_r4_run(path)
            end
        end
    end
    full=build_r4_thermal(c; spec = exp_spec)
    @test full.model_class=="nonconvex_nonlinear"
    @test any(F<:JuMP.GenericNonlinearExpr for (F, _) in list_of_constraint_types(full.model))
    @test build_r4_thermal(c; spec = ref).model_class=="nonconvex_quadratic"
    unsupported=solve_r4_thermal(c; spec = exp_spec, optimizer = opt, budget_sec = 60)
    @test !haskey(unsupported, "values")
    @test !unsupported["validation"]["model_pass"]
    @test_throws ErrorException solve_r4_thermal(c; optimizer = opt, budget_sec = 0)
    timed=solve_r4_thermal(c; spec = ref, optimizer = opt, budget_sec = 1e-12)
    @test !haskey(timed, "values")
    @test !timed["cost_optimization_complete"]
end
