# 原生指示对偶和完整MILP在同一部分带电域对照；本机许可验证，开放CI不运行。
using PaperRebuild, JuMP, Gurobi, TOML, Test
const PR=PaperRebuild
const ROOT=dirname(@__DIR__)
const OPT=optimizer_with_attributes(
    Gurobi.Optimizer,
    "OutputFlag"=>0,
    "Threads"=>1,
    "FeasibilityTol"=>1e-9,
    "OptimalityTol"=>1e-9,
    "IntFeasTol"=>1e-9,
    "MIPGap"=>1e-9,
)
@testset "R9-RE5 explicit switch and energized LP modes in the native-indicator adversary" begin
    d=TOML.parsefile(joinpath(ROOT, "configs/r7/recovery-hand.toml"))
    filter!(g->g["kind"]!="BES", d["devices"])
    d["electric"]["root_eligible"]=[1, 0]
    d["heat"]["load_MW"]=[[0.0], [0.0]]
    d["devices"][1]["heat_ratio"]=0.1
    c=with_r7_electric_domain(
        with_r7_critical_load(
            R7RecoveryCase(d),
            [0.0; 0.3;;];
            provenance = "synthetic 0.3 MW critical demand",
        ),
        "partial_energization_v1";
        provenance = "R9-RE5 whole recourse versus actual fixed-mode dual",
    )
    r=solve_r7_adversary(c; optimizer = OPT, budget_sec = 60)
    @test r["version"]=="r7_inner_energization_v1"
    @test r["status"]=="worst_loss_certified"
    @test r["validation"]["gap_certified"]
    @test r["validation"]["upper_bound_MWh"]≈0.3 atol=1e-7
    @test r["validation"]["lower_bound_MWh"]≈0.3 atol=1e-7
    @test all(
        !haskey(i, "added_topology") ||
            Set(keys(i["added_topology"]))==Set(["switch", "energized"]) for i in r["iterations"]
    )
    enum=audit_r7_faults(c; optimizer = OPT, budget_sec = 60)
    @test enum["upper_bound_MWh"]≈r["validation"]["upper_bound_MWh"] atol=1e-7
    path=mktempdir(joinpath(ROOT, "tmp"); cleanup = false)
    save_r7_adversary(c, r, joinpath(path, "inner"))
    @test read_r7_adversary(joinpath(path, "inner")).validation["gap_certified"]
    println("Energization native-indicator evidence: ", relpath(path, ROOT))
end
