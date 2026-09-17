using Test, JuMP, Clarabel
@testset "R3 audit distinguishes initialization and WMM" begin
    c=load_r2_case(joinpath(@__DIR__, "..", "configs", "r2", "single-source.toml"))
    r=solve_r3_projected_gradient(
        c;
        algorithm = :r3_pg_checked_v2,
        initial_flow = PaperRebuild.r2_flow_matrix(c),
        convex_optimizer = Clarabel.Optimizer,
        budget_sec = 60,
        max_iterations = 1,
    )
    fake=deepcopy(r["stages"][1])
    fake["spec"]["formulation"]="schpd_mc_v1"
    # 分类以完整spec而非阶段名称猜测；真实SCHPD全部近似标记一并保留。
    fake["spec"]=PaperRebuild.r2_spec_dict(R2Spec(formulation = :schpd_mc_v1))
    fake["model_pass"]=true
    push!(r["stages"], fake)
    loaded=(case = c, result = r, metadata = Dict("run_id"=>"analytic-audit"))
    a=audit_r3_failure(loaded)
    @test all(
        x["stage_index"]!=length(r["stages"]) for x in a["selected"] if x["role"]!="last_stage"
    )
    @test length(r3_stopping_evidence(c, r))==1
    @test a["input_sha256"]==c.sha256
end
