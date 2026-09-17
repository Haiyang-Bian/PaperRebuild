using Test, JuMP, Clarabel
const PR3=PaperRebuild
@testset "R3 v3 physical tangent and evidence" begin
    c=load_r2_case(joinpath(@__DIR__, "..", "configs", "r2", "single-source.toml"))
    s=PR3.r3_solve(
        c,
        ()->build_r3_subproblem(c, PR3.r2_flow_matrix(c)),
        Clarabel.Optimizer;
        budget_sec = 60,
    )
    @test validate_r3_solution(c, s).model_pass
    b=build_r3_physical_step(c, s; optimizer = Clarabel.Optimizer)
    @test r2_model_class(b.model)=="SOCP"
    set_silent(b.model)
    for key in ("tol_gap_abs", "tol_gap_rel", "tol_feas")
        set_optimizer_attribute(b.model, key, 1e-9)
    end
    optimize!(b.model)
    @test termination_status(b.model)==MOI.OPTIMAL
    candidate=PR3.r3_physical_candidate(c, s, b)
    @test candidate["objective_kind"]=="physical_violation"
    @test isfinite(PR3.r3_physical_merit(c, candidate["values"]).value)
    @test isfinite(PR3.r3_physical_score(c, candidate))
    @test candidate["status"]=="restoration_candidate"
    @test all(
        !haskey(candidate, k) for
        k in ("solver_bound", "raw_solver_bound", "solver_relative_gap", "bound_objective_kind")
    )
    stale=deepcopy(candidate)
    stale["solver_bound"]=s["operating_cost"]
    @test_throws ArgumentError validate_r3_solution(c, stale)
    er=first(x for x in b.physical_rows if x.equation=="R3-electric-equality")
    edge=c.data["electric"]["edges"][1]
    t=er.t
    electric_vars=[
        b.variables["v"][edge["from"], t],
        b.variables["ell"][1, t],
        b.variables["P_branch"][1, t],
        b.variables["Q_branch"][1, t],
    ]
    x0=[
        s["values"]["v"][edge["from"]][t],
        s["values"]["ell"][1][t],
        s["values"]["P_branch"][1][t],
        s["values"]["Q_branch"][1][t],
    ]
    direction0=[0.01, 0.005, -0.01, 0.003]
    obj=constraint_object(er.constraint)
    linear(z) = value(v->get(Dict(zip(electric_vars, z)), v, 0.0), obj.func)-obj.set.value
    nonlinear(z) = z[1]*z[2]-z[3]^2-z[4]^2
    @test abs(linear(x0)-nonlinear(x0))<=1e-10
    for h in (1e-3, 1e-4, 1e-5)
        @test abs(
            (nonlinear(x0+h*direction0)-nonlinear(x0-h*direction0))/(2h)-(
                linear(x0+h*direction0)-linear(x0-h*direction0)
            )/(2h),
        )<=1e-3
    end
    lr=PR3.r3_local_solve(
        c,
        s,
        Clarabel.Optimizer;
        mode = :dispatch,
        radius = 0.1,
        operation = nothing,
        deadline = PR3.r3_clock()+60,
    )
    lb=build_r3_local_step(c, s; radius = 0.1)
    @test PR3.r3_local_kkt_witness(lb.model, lr["values"], lr["kkt"])
    baddual=deepcopy(lr["kkt"])
    baddual["rows"][1]["raw_dual"][1]+=10
    @test !PR3.r3_local_kkt_witness(lb.model, lr["values"], baddual)
    # 二次支路方程的一阶展开：三个递减步长的余项为O(h²)。
    x=[1.0, 0.03, 0.12, 0.04]
    direction=[0.01, 0.005, -0.01, 0.003]
    g(x) = x[1]*x[2]-x[3]^2-x[4]^2
    derivative=sum([x[2], x[1], -2x[3], -2x[4]] .* direction)
    for h in (1e-3, 1e-4, 1e-5)
        @test abs((g(x+h*direction)-g(x-h*direction))/(2h)-derivative)<=1e-3
    end
    gate=Dict(
        "status"=>"local_checked",
        "switches"=>String[],
        "kkt"=>Dict("trusted"=>true),
        "trust_binding"=>false,
        "direction_norm"=>1e-8,
        "predicted_merit"=>1.0,
    )
    @test PR3.r3_stationarity_gate(gate, 1.0)
    for (key, bad) in (
        "trust_binding"=>true,
        "switches"=>["1:1"],
        "direction_norm"=>0.1,
        "kkt"=>Dict("trusted"=>false),
        "predicted_merit"=>0.9,
    )
        q=deepcopy(gate)
        q[key]=bad
        @test !PR3.r3_stationarity_gate(q, 1.0)
    end
    r=solve_r3_projected_gradient(
        c;
        algorithm = :r3_pg_checked_v3,
        initial_flow = PR3.r2_flow_matrix(c),
        convex_optimizer = Clarabel.Optimizer,
        budget_sec = 60,
        max_iterations = 2,
    )
    @test r["algorithm"]=="r3_pg_checked_v3"
    @test r["elapsed_sec"]<60
    @test !isempty(r["candidate_bank"])
    @test validate_r3_solution(c, r).physical_pass == (r["final_stage"]>0)
    tamper=deepcopy(r)
    tamper["candidate_bank"][1]["flow_sha256"]="bad"
    @test_throws ArgumentError validate_r3_solution(c, tamper)
    # 缺求解器/过期预算不得制造物理候选；恢复与最终调度都保留失败状态。
    absent=solve_r3_projected_gradient(
        c;
        algorithm = :r3_pg_checked_v3,
        initial_flow = PR3.r2_flow_matrix(c),
        budget_sec = 1,
    )
    @test absent["final_stage"]==0
    @test !absent["local_stationarity_checked"]
    @test PR3.r3_restore_physical(c, s, nothing; operation = nothing, deadline = Inf).status=="not_run_solver"
    @test PR3.r3_restore_physical(c, s, Clarabel.Optimizer; operation = nothing, deadline = 0.0).status=="budget_exhausted"
    mktempdir() do folder
        run=save_r3_run(c, r; root = folder)
        @test read_r3_run(run).result["algorithm"]=="r3_pg_checked_v3"
    end
end

@testset "R3 frozen boundary physical restoration" begin
    root=joinpath(@__DIR__, "..", "results", "summaries", "r3-v3", "audit")
    c=load_r2_case(joinpath(root, "case.toml"))
    a=TOML.parsefile(joinpath(root, "failure.toml"))
    s=deepcopy(only(x["record"] for x in a["selected"] if x["role"]=="minimum_violation"))
    s=PR3.reconstruct_r3_pressure(c, s)
    s["v3_physical_review"]=true
    @test !validate_r3_solution(c, s).physical_pass
    o=PR3.r3_operation_from_dict(s["operation"])
    rr=PR3.r3_restore_physical(
        c,
        s,
        Clarabel.Optimizer;
        operation = o,
        deadline = PR3.r3_clock()+60,
    )
    @test rr.status=="physical_A1_pass"
    @test validate_r3_solution(c, rr.candidate).physical_pass
    @test rr.candidate["status"]=="restoration_candidate"
    @test all(
        row["after"]<row["before"] && row["ratio"]>=0.1 for row in rr.trace if row["accepted"]
    )
    # 构造仅用于验证器的阶段证据，失败终求不能覆盖已经合格的恢复候选。
    center=deepcopy(s)
    center["stage"]="dispatch"
    pressure=deepcopy(s)
    pressure["stage"]="pressure_reconstruction"
    pressure["sensitivity_source_stage"]=1
    r=Dict{String,Any}(
        "stages"=>[center, pressure],
        "operation"=>PR3.r3_operation_dict(o),
        "physical_restoration"=>Dict("source_stage"=>1, "trace"=>rr.trace),
    )
    r["candidate_bank"]=PR3.r3_v3_candidates(c, r["stages"])
    @test length(r["candidate_bank"])==1
    @test length(r["candidate_bank"][1]["roles"])==4
    @test PR3.r3_validate_v3(c, r)
    altered=deepcopy(r)
    altered["physical_restoration"]["trace"][1]["after"]*=2
    @test_throws ArgumentError PR3.r3_validate_v3(c, altered)
end
