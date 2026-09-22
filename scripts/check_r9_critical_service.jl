# 第7.5节服务范围映射；解析/优化证据由独立专项测试生成。
using Test, TOML, PaperRebuild
root=dirname(@__DIR__)
c=TOML.parsefile(joinpath(root, "docs/reading/ch07/resilience-load-service.toml"))
source=TOML.parsefile(joinpath(root, c["source_review"]))
@testset "R9 critical-load adoption and formula mapping" begin
    @test c["schema"]=="r9-resilience-load-service-contract-v1"
    @test c["source_sha256"]==source["source_sha256"]
    @test c["pdf_pages"]==[112, 139]
    @test c["service_objective"]=="critical_electric_v1"
    @test c["ordinary_and_heat_physical_demands_preserved"]
    for key in (
        "ordinary_and_heat_secondary_optimization",
        "old_results_rewritten",
        "event_grid_conversion_implemented",
        "chapter_7_5_scale_optimization_performed",
        "author_unique_node_allocation_recovered",
    )
        @test !c[key]
    end
    page=read(joinpath(root, c["human_page"]), String)
    @test Set(f["id"] for f in c["formula"])==Set(["R9-RL1", "R9-RL2", "R9-RL3"])
    for f in c["formula"]
        @test occursin("\\tag{"*f["id"]*"}", page)
        @test occursin(f["id"], read(joinpath(root, f["test"]), String))
        for api in f["api"]
            @test isdefined(PaperRebuild, Symbol(api))
        end
        for path in f["implementation"]
            @test isfile(joinpath(root, path))
        end
    end
    for command in c["test_commands"]
        @test isfile(joinpath(root, command)) && occursin(command, page)
    end
    # 条件输入核查：旧等额分配不能容纳同一时点13.75 MW的重要需求；不调整父输入。
    pre=c["allocation_preflight"]
    protocol=TOML.parsefile(joinpath(root, pre["protocol"]))
    original=TOML.parsefile(joinpath(root, "docs/reading/ch07/inputs.toml"))
    finding=only(x for x in source["finding"] if x["id"]=="R9-RS02")
    @test protocol["electric"]["node_allocation"]=="equal_apparent_load_at_original_nodes_1_to_43; root_44_zero"
    counts=[length(finding[key]) for key in ("nodes_figure_7_12", "nodes_figure_7_14")]
    available=counts .*
              (original["base"]["electric_peak_MVA"]*protocol["electric"]["power_factor"]/43)
    @test counts==pre["node_counts"]
    @test available≈pre["available_total_peak_MW"] atol=1e-10
    @test pre["target_MW"]==original["resilience"]["critical_active_capacity_MW"] &&
          all(available .< pre["target_MW"]) &&
          !pre["optimization_performed"]
end
