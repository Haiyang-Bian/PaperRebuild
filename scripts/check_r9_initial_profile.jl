# 初态表示/公式/API与预优化证据契约；不把映射通过当作科学验证。
using Test, TOML, SHA, PaperRebuild
root=dirname(@__DIR__)
d=TOML.parsefile(joinpath(root, "docs/reading/ch07/resilience-initial-profile.toml"))
@testset "R9-RI1/RI3 initial profile mapping and preflight scope" begin
    @test d["input_schema"]=="r7-initial-profile-v2"
    @test d["maximum_normalized_quadrature_error"]==1e-10
    @test d["legacy_piecewise_constant_preserved"]
    for key in (
        "old_results_rewritten",
        "node_method_history_inferred",
        "reverse_flow_optimization_added",
        "scale_input_frozen",
        "scale_optimization_performed",
    )
        @test d[key]===false
    end
    page=read(joinpath(root, d["human_page"]), String)
    @test [x["id"] for x in d["formula"]]==["R9-RI$i" for i in 1:3]
    for x in d["formula"]
        @test occursin("\\tag{"*x["id"]*"}", page)
        @test occursin(x["id"], read(joinpath(root, x["test"]), String))
        for api in x["api"]
            @test isdefined(PaperRebuild, Symbol(api))
        end
    end
    for script in d["test_commands"]
        @test isfile(joinpath(root, script)) && occursin(script, page)
    end
    @test occursin(d["quadrature_reference"], page)
    evidence=TOML.parsefile(joinpath(root, d["input_preflight"]))
    @test !evidence["optimization_performed"] && !evidence["scale_input_frozen"]
    @test evidence["origin"]=="preoptimization_project_input_audit_not_frozen_scale_case"
    for (key, path) in (
        "audit_script_sha256"=>"scripts/audit_r9_resilience_input.jl",
        "engineering_protocol_sha256"=>evidence["engineering_protocol"],
        "pipe_replay_sha256"=>"src/networks/r7_pipe_state.jl",
    )
        @test evidence[key]==bytes2hex(sha256(read(joinpath(root, path))))
    end
    @test evidence["dt_h"]==0.25 && length(evidence["profiles"])==74
    @test evidence["total_peak_MW"]≈41.103 atol=1e-10
    @test evidence["maximum_uniform_outlet_error_K"]≈maximum(
        abs(p["uniform_first_outlet_error_K"]) for p in evidence["profiles"]
    ) atol=1e-12
end
