using Test, CSV
include("audit_r7_lossy_flow.jl")
length(ARGS)==2||error("usage: check_r7_lossy_flow_audit.jl REPORT AUDIT")
report, audit=abspath.(ARGS)
cfg=TOML.parsefile(joinpath(audit, "audit.toml"))
@testset "R7-H5 independent heat/cost identity and scope" begin
    @test cfg["origin"]=="synthetic"
    @test cfg["report_manifest_sha256"]==joint_hash(joinpath(report, "report-hashes.toml"))
    actual=joint_manifest(audit)
    delete!(actual, "audit.toml")
    @test actual==cfg["files"]
    rows=lossy_energy_rows(report)
    io=IOBuffer()
    CSV.write(io, rows)
    @test take!(io)==read(joinpath(audit, "energy-cost.csv"))
    for r in rows
        @test r.cost_identity_residual_USD<=1e-6*max(1, abs(r.cost_USD))
        @test r.heat_balance_residual_MWh<=1e-6
        @test r.electric_balance_residual_MWh<=1e-6
        @test abs(r.thermal_inventory_change_MWh)<=1e-6
        @test abs(r.battery_inventory_change_MWh)<=1e-6
        @test r.normal_loss_MWh>=-1e-8
        @test r.base_cost_USD≈192 atol=1e-8
        @test r.loss_effect_USD≈-80r.normal_loss_MWh atol=1e-8
        r.UA_W_K==0&&(@test abs(r.normal_loss_MWh)<=1e-8)
    end
end
