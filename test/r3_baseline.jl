using Test, JuMP, Clarabel
@testset "R3 baseline geometry, evidence and compatibility" begin
    P=PaperRebuild
    c=load_r2_case(joinpath(@__DIR__, "..", "configs", "r2", "two-source.toml"))
    target=repeat([1.4, 1.6], 1, 4)
    for (geometry, expected) in
        ((:physical_euclidean, [1.25, 1.75]), (:normalized_euclidean, [1.34, 1.84]))
        p=P.r3_project(c, target, Clarabel.Optimizer; geometry)
        @test p["status"]=="projected"
        @test maximum(abs, P.r3_matrix(p["flow"])-repeat(expected, 1, 4))<=1e-4
        @test P.r3_projection_witness(c, p["values"])
        again=P.r3_project(c, P.r3_matrix(p["flow"]), Clarabel.Optimizer; geometry)
        @test maximum(abs, P.r3_matrix(again["flow"])-P.r3_matrix(p["flow"]))<=1e-4
        spec=R3BaselineSpec(; geometry)
        g=reshape([1.0, 2.0, 0.0, 4.0], 2, 2)
        w=reshape([1.0, 2.0, 0.0, 2.0], 2, 2)
        direction, gamma=P.r3_baseline_direction(g, w, spec)
        @test direction[3]==0
        @test maximum(abs, gamma*direction ./ ifelse.(w .> 0, w, 1.0))≈0.1
        for scale in (1e-3, 1e3)
            d2, a2=P.r3_baseline_direction(g/scale, w*scale, spec)
            @test a2*d2≈scale*gamma*direction
        end
    end
    @test_throws ArgumentError R3BaselineSpec(geometry = :unknown)
    @test_throws ArgumentError R3BaselineSpec(initial_displacement = 0)
    c=load_r2_case(joinpath(@__DIR__, "..", "configs", "r2", "single-source.toml"))
    initial=P.r2_flow_matrix(c)
    r=solve_r3_baseline(
        c;
        initial_flow = initial,
        convex_optimizer = Clarabel.Optimizer,
        budget_sec = 60,
        max_iterations = 2,
    )
    @test r["algorithm"]=="r3_paper_structure_v1"
    @test !isempty(r["iterations"])
    @test all(!occursin("restoration", s["stage"]) for s in r["stages"])
    @test validate_r3_solution(c, r).physical_pass==(r["final_stage"]>0)
    @test length(r3_stopping_evidence(c, r))==1+count(x["accepted"] for x in r["iterations"])
    evidence=r3_stopping_evidence(c, r)
    @test last(evidence)["stage"]==only(
        t["stage"] for t in last(r["iterations"])["trials"] if t["accepted"]
    )
    repeated=deepcopy(r)
    push!(repeated["stages"], deepcopy(last(repeated["stages"])))
    @test r3_stopping_evidence(c, repeated)==evidence
    bad=deepcopy(r)
    bad["strict_cost_optimal"]=true
    @test_throws ArgumentError validate_r3_solution(c, bad)
    for it in r["iterations"]
        @test validate_r3_iteration(c, it; stages = r["stages"]).pass
    end
    @test length(r["candidate_bank"])==length(unique(x["flow_sha256"] for x in r["candidate_bank"]))
    if !isempty(r["candidate_bank"])
        bad=deepcopy(r)
        bad["candidate_bank"][1]["flow_sha256"]="changed"
        @test_throws ArgumentError validate_r3_solution(c, bad)
    end
    trusted=findfirst(x->haskey(x, "gradient"), r["iterations"])
    @test !isnothing(trusted)
    if !isnothing(trusted)
        stage=r["stages"][r["iterations"][trusted]["stage"]]
        @test P.r3_baseline_kkt_witness(c, stage, nothing)
        bad=deepcopy(stage)
        bad["sensitivity"]["kkt"]["rows"][1]["raw_dual"][1]+=10
        @test !P.r3_baseline_kkt_witness(c, bad, nothing)
        modified=deepcopy(r["iterations"][trusted])
        modified["gradient"][1][1]+=1
        @test !validate_r3_iteration(c, modified; stages = r["stages"]).pass
    end
    mktempdir() do folder
        directory=save_r3_run(c, r; root = folder)
        loaded=read_r3_run(directory)
        @test loaded.result["algorithm"]==r["algorithm"]
        @test length(compare_r3_baselines([loaded, loaded]))==2
        other=deepcopy(loaded)
        other.result["budget_sec"]=10
        @test_throws ArgumentError compare_r3_baselines([loaded, other])
        open(joinpath(directory, "run.toml"), "a") do io
            write(io, "\n# tampered\n")
        end
        @test_throws ArgumentError read_r3_run(directory)
    end
    absent=solve_r3_baseline(c; initial_flow = initial, budget_sec = 1)
    @test absent["final_stage"]==0
    @test absent["outer_status"]=="subproblem_unresolved"
    expired=solve_r3_baseline(c; initial_flow = initial, budget_sec = 1e-9)
    @test expired["outer_status"]=="budget_exhausted"
    @test_throws ArgumentError solve_r3_baseline(c; initial_flow = initial, budget_sec = 601)
end
