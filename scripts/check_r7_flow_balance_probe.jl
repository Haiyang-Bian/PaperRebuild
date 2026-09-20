using Test, TOML, SHA
include("r7_normal_flow_study.jl")
length(ARGS)==1 || error("usage: check_r7_flow_balance_probe.jl PROBE")
dir=abspath(ARGS[1]);
hashes=TOML.parsefile(joinpath(dir, "files.toml"))["files"]
for (p, h) in hashes
    !isabspath(p)&&!occursin(':', p)&&!occursin('\\', p)&&all(
        x->!(x in ("", ".", "..")),
        split(p, '/'),
    ) || error("探针路径非法")
    bytes2hex(sha256(read(joinpath(dir, split(p, '/')...))))==h || error("等价守恒探针篡改")
end
a=flow_read(joinpath(dir, "record"));
r=a.result
@testset "R7-F6 redundant conservation formulation witness" begin
    @test r["formulation_variant"]=="explicit_redundant_network_energy_v1"
    @test r["extra_constraint_source_sha256"]==bytes2hex(
        sha256(read(joinpath(dir, "probe-source.jl"))),
    )
    @test r["candidate_accepted"]
    @test r["domain_cost_complete"]
    @test a.validation["cost_USD"]≈118.4 atol=1e-6
    # 独立原关系与能量平衡由保存原值复算，新增行不能让违反原关系的点过关。
    q=a.validation["normal_validation"]
    @test q["model_pass"]&&q["pipe_reference_pass"]
    @test count(x->x["id"]=="reference-network-energy", q["rows"])==a.case.data["periods"]*length(
        a.case.data["probabilities"],
    )
    @test all(x["pass"] for x in q["rows"] if x["id"]=="reference-network-energy")
end
