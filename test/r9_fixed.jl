using Test, JuMP, TOML, SHA

@testset "R9-F1:F2 exact rank and bounded terminal coordinates" begin
    A=[1.0 1.0; 2.0 2.0]
    for rhs in ([2.0, 4.0], [2.0, nextfloat(4.0)])
        r=r9_terminal_coordinates(A, rhs, [-10.0, -10.0], [10.0, 10.0])
        @test r.rank==1
        @test size(r.basis)==(2, 1)
        @test r.offset≈[1.0, 1.0] atol=1e-14
        @test r.exact_binary_consistent==(rhs[2]==4.0)
        for z in (-r.radius, -1.0, 0.0, 1.0, r.radius)
            residual=abs.(A*(r.offset+r.basis*[z])-rhs)
            @test maximum(residual)<1e-10
            @test all(residual .<= r.row_error_bound_K .+ 2e-14)
        end
    end
    near=[1.0 1.0; 1.0 nextfloat(1.0)]
    r=r9_terminal_coordinates(near, [2.0, 2.0], zeros(2), fill(3.0, 2))
    @test r.rank==2
    @test size(r.basis)==(2, 0)
    @test near*r.offset==[2.0, 2.0]
    @test r9_terminal_coordinates(zeros(0, 0), Float64[], Float64[], Float64[]).rank==0
    @test_throws ArgumentError r9_terminal_coordinates(
        A,
        [2.0, 4.001],
        fill(-10.0, 2),
        fill(10.0, 2),
    )
    @test_throws ArgumentError r9_terminal_coordinates(A, [2.0, 4.0], zeros(1), ones(2))
    @test_throws ArgumentError r9_terminal_coordinates(A, [NaN, 4.0], zeros(2), ones(2))
    @test_throws ArgumentError r9_terminal_coordinates(A, [2.0, 4.0], ones(2), zeros(2))
end

@testset "R9 fixed-flow forward witness and independent terminal contract" begin
    root=normpath(joinpath(@__DIR__, ".."))
    archive=joinpath(root, "results/summaries/r9-flow-reference-20260921-v2")
    index=TOML.parsefile(joinpath(archive, "index.toml"))
    object(h) = joinpath(archive, "objects", h)
    c=load_r9_pv_case(object(index["case"]))
    parent=only(r for r in index["runs"] if r["id"]=="vf_vt")
    saved=TOML.parsefile(object(parent["payload"]["stage.toml"]))["values"]
    m=permutedims(hcat(saved["m_pipe"]...))
    originalhash=c.sha256
    b=build_r9_reduced_model(c; mode = :VF_VT, flow_schedule = m, terminal = :rank_checked_rhs)
    @test !has_values(b.model)
    @test b.class=="SOCP"
    @test b.fixed_flows
    @test b.flow_schedule==m
    @test c.sha256==originalhash
    cert=b.terminal_certificate
    @test cert["rank_exact_binary"]==32
    @test cert["free_source_count"]==16
    @test !cert["reference_witness_used"]
    @test maximum(cert["row_error_bound_K"])<=1e-10
    @test all(x.pass for x in b.constant_checks)
    @test !haskey(b.constraints, "R9-P6")
    @test length(b.constraints["R9-F2-source-bound"])==96
    @test_throws ArgumentError build_r9_reduced_model(c; mode = :VF_VT)
    @test_throws ArgumentError build_r9_reduced_model(
        c;
        mode = :VF_VT,
        flow_schedule = m,
        terminal = :reference_anchored,
    )
    @test_throws ArgumentError build_r9_reduced_model(c; mode = :CF_VT, flow_schedule = m)
    bad=copy(m)
    bad[:, end].*=1.01
    @test_throws ArgumentError build_r9_reduced_model(c; mode = :VF_VT, flow_schedule = bad)
    # 只投影保存源温到已认证终端空间；不优化，不改变终端解释或引入参考锚定。
    U=permutedims(hcat(cert["basis"]...))
    centre=b.temperature_centre_K
    original=[saved["tau_S_port"][j][t]-centre for (j, t) in cert["source_coordinates"]]
    y=U'*(original-cert["offset_K"])
    predicted=cert["offset_K"]+U*y
    # 反例：误差界很小不能证明控制量改变很小；此表示不作为默认/PG修复。
    @test maximum(abs, predicted-original)>10.0
    @test maximum(abs, predicted-original)≈16.441653850438172 atol=1e-6
    b=build_r9_reduced_model(c; mode = :VF_VT, flow_schedule = m, terminal = :roundoff_band)
    @test length(b.constraints["R9-F3-terminal-band"])==148
    @test b.terminal_certificate["radius_K"]==2.0^-34
    @test !haskey(b.variables, "r9_terminal_coordinates")
    # 舍入区间对照保留保存源温，不将反例中的投影温度灌入运行。
    point=Dict(x=>0.0 for x in all_variables(b.model))
    for (j, node) in enumerate(c.data["heat"]["nodes"]), t in 1:c.data["T"]
        node["role"]=="source" || continue
        expression=b.variables["tau_S_port"][j, t]
        a, var=only(collect(linear_terms(expression)))
        point[var]=(saved["tau_S_port"][j][t]-constant(expression))/a
    end
    for key in ("P_device", "H_device", "P_grid", "Q_grid", "P_branch", "Q_branch", "v", "ell")
        a=b.variables[key]
        val=ndims(a)==1 ? saved[key] : permutedims(hcat(saved[key]...))
        for i in eachindex(a)
            point[a[i]]=val[i]
        end
    end
    evaluate(a) = begin
        x=map(expr->value(v->point[v], expr), a)
        ndims(x)==1 ? collect(x) : [collect(row) for row in eachrow(x)]
    end
    values=Dict(k=>evaluate(a) for (k, a) in b.variables)
    for side in ("S", "R")
        @test maximum(
            abs(
                PaperRebuild.r3_mass_replay(c, values, p, t, side).out-values["tau_"*side*"_out"][p][t],
            ) for p in axes(m, 1), t in axes(m, 2)
        ) < 1e-9
    end
    @test r9_daily_heat_balance(c, values).residual_MWh<1e-9
    @test all(x.pass for x in r9_flow_terminal_rows(c, Dict("values"=>values)))
    @test maximum(Base.values(primal_feasibility_report(b.model, point; atol = 0.0)); init = 0.0)<1e-9
    stage=PaperRebuild.r3_solve(c, ()->b, nothing)
    stage["values"]=values
    stage["objective"]=PaperRebuild.r3_operating_cost(c, values)
    stage["operating_cost"]=stage["objective"]
    stage["solver_objective"]=stage["objective"]
    record=Dict(
        "schema"=>"r9-fixed-run-v1",
        "input_sha256"=>c.sha256,
        "mode"=>"VF_VT",
        "terminal_interpretation"=>"roundoff_band",
        "flow_schedule"=>PaperRebuild.r2_extract(m),
        "flow_sha256"=>PaperRebuild.r2_flow_hash(m),
        "stage"=>stage,
        "terminal_certificate"=>b.terminal_certificate,
        "constant_checks"=>[
            Dict(string(k)=>getproperty(x, k) for k in keys(x)) for x in b.constant_checks
        ],
    )
    @test validate_r9_fixed_solution(c, record).physical_pass
    broken=deepcopy(record)
    broken["flow_sha256"]="modified"
    @test_throws ArgumentError validate_r9_fixed_solution(c, broken)
    broken=deepcopy(record)
    broken["terminal_certificate"]["radius_K"]=1e-3
    @test_throws ArgumentError validate_r9_fixed_solution(c, broken)
    broken=deepcopy(record)
    broken["stage"]["values"]["tau_S_in"][1][end]+=1e-7
    @test !validate_r9_fixed_solution(c, broken; check_representation = false).representation_pass
    @test_throws ArgumentError solve_r9_fixed_case(c, m; budget_sec = 601)
    stopped=solve_r9_fixed_case(c, m; budget_sec = 0)
    @test stopped["status"]=="time_limit_no_solution"
    @test !stopped["validation"]["model_pass"]
    @test !stopped["kkt"]["trusted"]
end
