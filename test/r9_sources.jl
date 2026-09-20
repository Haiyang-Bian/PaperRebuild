@testset "R9 original topology, units, arithmetic and missing-input gates" begin
    folder=joinpath(@__DIR__, "../docs/reading/ch07")
    b=load_r9_sources(folder)
    a=audit_r9_sources(b)
    @test a["electric"]==Dict("nodes"=>44, "edges"=>43, "connected"=>true, "cycles"=>0)
    @test a["heat"]==Dict("nodes"=>38, "edges"=>37, "connected"=>true, "cycles"=>0)
    @test a["base_derived_heat_capacity_MW"]≈9.0
    @test a["eb_electric_capacities_MW"]≈[1/0.92, 1.2/0.93]
    @test !a["original_input_complete"] && !a["optimization_performed"]
    d=b.data["inputs.toml"]
    @test r9_tariff(d, [0, 4, 5, 7, 8, 11, 12, 16, 17, 20, 21, 23])≈[
        258.9,
        258.9,
        606.8,
        606.8,
        1034.7,
        1034.7,
        606.8,
        606.8,
        1034.7,
        1034.7,
        258.9,
        258.9,
    ]
    @test count(==(1034.7), a["tariff_CNY_MWh"])==8
    @test count(==(606.8), a["tariff_CNY_MWh"])==8
    @test count(==(258.9), a["tariff_CNY_MWh"])==8
    for hours in ([24.0], [-1.0], [NaN], [Inf])
        @test_throws ErrorException r9_tariff(d, hours)
    end
    dd=deepcopy(d)
    push!(dd["base"]["tariff"]["peak_intervals_h"], [0, 1])
    @test_throws ErrorException r9_tariff(dd, [0])
    for s in ("7.2", "7.3", "7.4", "7.5")
        gate=r9_original_input_gate(b, s)
        @test !gate["original_input_ready"] && !isempty(gate["gaps"])
        @test_throws ErrorException r9_original_input_gate(b, s; require_complete = true)
    end
    @test_throws ErrorException r9_original_input_gate(b, "7.6")
    for (n, edges, root) in
        ((2, [[1, 1]], 1), (2, [[1, 2], [2, 1]], 1), (3, [[1, 2]], 1), (2, [[1, 3]], 1))
        @test_throws ErrorException PaperRebuild.r9_graph(n, edges, root)
    end
    @test_throws ErrorException PaperRebuild.r9_graph(3, [[1, 2], [2, 3], [3, 1]], 1; tree = true)
    @test PaperRebuild.r9_graph(3, [[1, 2], [2, 3], [3, 1]], 1)["cycles"]==1
    @test only(filter(r->r["id"]=="R9-Q01", a["rows"]))["status"]=="difference_requires_interpretation"
    for key in ("Q08-4B", "Q08-4C")
        @test only(filter(r->r["id"]==key, a["rows"]))["status"]=="difference_requires_interpretation"
    end
    @test only(filter(r->r["id"]=="7-19-cost-4A", a["rows"]))["status"]=="consistent_with_printed_rounding"
    for mutate in (
        x->(x["topology.toml"]["heat"]["edges"][1]=[1, 39]),
        x->(x["inputs.toml"]["resilience"]["penalty_CNY_MWh"]=10.0),
        x->(x["inputs.toml"]["reserve"]["market_role"]="strategic"),
        x->(x["inputs.toml"]["base"]["electric_peak_is_active_power"]=true),
        x->(x["reported-results.toml"]["source_sha256"]="0"^64),
        x->empty!(x["inputs.toml"]["gaps"]),
        x->pop!(x["reported-results.toml"]["four_modes"]["cost_CNY"]),
        x->(x["reported-results.toml"]["resilience"]["normal_cost_CNY"][1]=NaN),
    )
        c=deepcopy(b.data)
        mutate(c)
        @test_throws ErrorException PaperRebuild.r9_source_check(c)
    end
end
