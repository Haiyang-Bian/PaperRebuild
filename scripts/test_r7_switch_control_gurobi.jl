# 新开关域的真实原生指示对偶与完整故障穷举对照。
using PaperRebuild, JuMP, Gurobi, TOML, Test
root=dirname(@__DIR__)
opt=optimizer_with_attributes(
    Gurobi.Optimizer,
    "OutputFlag"=>0,
    "Threads"=>1,
    "FeasibilityTol"=>1e-9,
    "OptimalityTol"=>1e-9,
    "IntFeasTol"=>1e-9,
    "MIPGap"=>1e-9,
)
@testset "R9-RW1 native adversary respects immutable healthy lines" begin
    d=TOML.parsefile(joinpath(root, "configs/r7/recovery-hand.toml"))
    filter!(g->g["kind"]!="BES", d["devices"])
    d["electric"]["root_eligible"]=[1, 0]
    d["heat"]["load_MW"]=[[0.0], [0.0]]
    d["devices"][1]["heat_ratio"]=0.1
    c=with_r7_switch_control(
        with_r7_electric_domain(
            with_r7_critical_load(
                R7RecoveryCase(d),
                [0.0; 0.3;;];
                provenance = "synthetic critical split",
            ),
            "partial_energization_v1";
            provenance = "no downstream grid-forming source",
        ),
        [];
        provenance = "all healthy lines mechanically immutable",
    )
    r=solve_r7_adversary(c; optimizer = opt, budget_sec = 60)
    @test r["status"]=="worst_loss_certified"
    @test r["validation"]["gap_certified"]
    @test r["validation"]["upper_bound_MWh"]≈0.3 atol=1e-7
    @test r["validation"]["lower_bound_MWh"]≈0.3 atol=1e-7
    reference=audit_r7_faults(c; optimizer = opt, budget_sec = 60)
    @test reference["all_faults_attempted"]
    @test reference["upper_bound_MWh"]≈r["validation"]["upper_bound_MWh"] atol=1e-7
    folder=mktempdir(joinpath(root, "tmp"); cleanup = false)
    save_r7_adversary(c, r, joinpath(folder, "native"))
    @test read_r7_adversary(joinpath(folder, "native")).validation["gap_certified"]
    println("Switch native-indicator evidence: ", relpath(folder, root))
end
