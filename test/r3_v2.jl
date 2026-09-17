using Test, JuMP, Clarabel

@testset "R3 four operation modes and local candidate" begin
    for name in ("single-source", "two-source")
        c=load_r2_case(joinpath(@__DIR__, "..", "configs", "r3", name*"-four-modes-v1.toml"))
        m=PaperRebuild.r2_flow_matrix(c)
        for mode in (:CF_CT, :CF_VT, :VF_CT, :VF_VT)
            op=R3OperationSpec(c; mode)
            b=build_r3_subproblem(c, m; operation = op)
            @test b.class=="SOCP"
            j=findfirst(n->n["role"]=="load", c.data["heat"]["nodes"])
            @test !is_fixed(b.variables["tau_R_port"][j, 1])
            lo, hi, width=PaperRebuild.r3_flow_box(c, op)
            @test all(width[:, 5:end] .== 0)
            @test all(width[:, 1:4] .== 0)==PaperRebuild.r3_is_cf(op)
        end
        op=R3OperationSpec(c; mode = :CF_CT)
        run=solve_r3_projected_gradient(
            c;
            algorithm = :r3_pg_checked_v2,
            operation = op,
            convex_optimizer = Clarabel.Optimizer,
            budget_sec = 60,
        )
        @test isempty(run["iterations"])
        @test run["best_subproblem_stage"]>0
        i=run["best_subproblem_stage"]
        @test validate_r3_solution(c, run["stages"][i]).model_pass
        center=run["stages"][i]
        op2=R3OperationSpec(c; mode = :VF_VT)
        localstep=PaperRebuild.r3_local_solve(
            c,
            center,
            Clarabel.Optimizer;
            mode = :dispatch,
            radius = 0.1,
            operation = op2,
            deadline = PaperRebuild.r3_clock()+60,
        )
        @test localstep["status"]=="local_checked"
        @test maximum(abs, PaperRebuild.r3_matrix(localstep["flow"])[:, 5:end]-m[:, 5:end])<1e-6
        corrupted=deepcopy(center)
        corrupted["operation"]["mode"]="VF_VT"
        @test_throws ArgumentError validate_r3_solution(c, corrupted)
    end
    c=load_r2_case(joinpath(@__DIR__, "..", "configs", "r2", "single-source.toml"))
    @test_throws ArgumentError R3OperationSpec(c; mode = :INVALID)
    @test_throws ArgumentError solve_r3_projected_gradient(
        c;
        algorithm = :r3_pg_checked_v2,
        operation = R3OperationSpec(c; mode = :CF_CT),
        initial_flow = fill(1.1, 1, 4),
    )
    @test_throws ArgumentError solve_r3_projected_gradient(c; algorithm = :bad)
    @test_throws ArgumentError build_r3_local_step(c, Dict(); radius = 0.3)
    @test solve_r3_reference(c; operation = R3OperationSpec(c; mode = :CF_CT))["status"]=="no_verified_physical_solution"
end

@testset "R3 v2 trace and failure propagation" begin
    c=load_r2_case(joinpath(@__DIR__, "..", "configs", "r2", "single-source.toml"))
    m=PaperRebuild.r2_flow_matrix(c)
    r=solve_r3_projected_gradient(
        c;
        algorithm = :r3_pg_checked_v2,
        initial_flow = m,
        convex_optimizer = Clarabel.Optimizer,
        budget_sec = 60,
        max_iterations = 12,
    )
    @test validate_r3_solution(c, r).physical_pass
    @test all(validate_r3_iteration(c, row; stages = r["stages"]).pass for row in r["iterations"])
    @test !any(s["stage"]=="direct_repair" for s in r["stages"])
    for row in r["iterations"]
        row["accepted"] || continue
        changed=deepcopy(row)
        changed["merit"]+=1
        @test !validate_r3_iteration(c, changed; stages = r["stages"]).pass
    end
    absent=solve_r3_projected_gradient(
        c;
        algorithm = :r3_pg_checked_v2,
        initial_flow = m,
        budget_sec = 1,
    )
    @test absent["final_stage"]==0
    @test !absent["outer_converged"]
    expired=PaperRebuild.r3_local_solve(
        c,
        Dict(),
        Clarabel.Optimizer;
        mode = :dispatch,
        radius = 0.1,
        operation = nothing,
        deadline = 0.0,
    )
    @test expired["status"]=="budget_exhausted"
    scaled=PaperRebuild.r3_solve(
        c,
        ()->build_r3_subproblem(c, m; rescale_cones = true),
        Clarabel.Optimizer;
        sensitivity = true,
    )
    @test validate_r3_solution(c, scaled).model_pass
    @test scaled["rescale_cones"]
end

@testset "R3 full thermal partials and joint local SOCP" begin
    for case in ("single-source", "two-source"), mode in (:dispatch, :diagnostic)
        c=load_r2_case(joinpath(@__DIR__, "..", "configs", "r2", case*".toml"))
        m=PaperRebuild.r2_flow_matrix(c)
        mode==:diagnostic && (m .*= 0.6)
        r=PaperRebuild.r3_solve(c, ()->build_r3_subproblem(c, m; mode), Clarabel.Optimizer)
        @test haskey(r, "values")
        b=build_r3_subproblem(c, m; mode)
        partials=PaperRebuild.r3_thermal_partials(c, b, r["values"], m)
        vals=Dict(v=>0.0 for v in all_variables(b.model))
        for (key, vs) in b.variables
            raw=r["values"][key]
            a=ndims(vs)==2 ? PaperRebuild.r3_matrix(raw) : raw
            for i in eachindex(vs)
                vals[vs[i]]=a[i]
            end
        end
        center=[vals[v] for v in all_variables(b.model)]
        # 同时扰动各管，质量守恒的端口流率随管流变化；历史不动。
        direction=copy(m)
        for step in (1e-4, 1e-5, 1e-6)
            bp=build_r3_subproblem(c, m+step*direction; mode)
            bm=build_r3_subproblem(c, m-step*direction; mode)
            function atstate(built, row)
                cr=built.constraints[row.id][row.index]
                state=Dict(zip(all_variables(built.model), center))
                return value(v->state[v], constraint_object(cr).func)-normalized_rhs(cr)
            end
            for row in partials.rows
                fd=(atstate(bp, row)-atstate(bm, row))/(2step)
                analytic=sum(row.derivative .* direction)
                @test abs(fd-analytic)/max(1, abs(analytic))<1e-3
            end
        end
        localmodel=build_r3_local_step(c, r; mode)
        @test localmodel.class=="SOCP"
        @test !is_fixed(localmodel.variables["m_pipe"][1, 1])
    end
end
