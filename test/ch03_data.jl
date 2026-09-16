# 独立数据测试不依赖网络、大文件或论文原件；输入为项目合成fixture（MIT）。
using Test, SHA, TOML
include(joinpath(@__DIR__, "..", "scripts", "ch03_data.jl"))
using .Ch03Data

@testset "Ch03 defensive data import" begin
    @test Ch03Data.number(" 1.2e-3; ") == 0.0012
    @test Ch03Data.number("-Inf"; finite = false) == -Inf
    for invalid in (missing, "", "1/1000", "1 kW", "=A1", "NaN", Inf)
        @test_throws ErrorException Ch03Data.number(invalid)
    end
    @test Ch03Data.literal_matrix("mpc.bus=[1 2; % note\n3 4;];", "bus", 2) == [1.0 2; 3 4]
    @test_throws ErrorException Ch03Data.literal_matrix("mpc.bus=[1 2;3;];", "bus", 2)
    @test_throws ErrorException Ch03Data.literal_matrix("mpc.bus=[system('x') 2;];", "bus", 2)
    @test Ch03Data.graph_metrics(1:3, [(1, 2), (2, 3)])["radial"]
    @test Ch03Data.graph_metrics(1:3, [(1, 2), (2, 3), (3, 1)])["cycles"] == 1
    @test Ch03Data.graph_metrics(1:3, [(1, 2)])["components"] == 2
    @test_throws ErrorException Ch03Data.graph_metrics([1, 1], [(1, 2)])
    @test_throws ErrorException Ch03Data.graph_metrics(1:3, [(1, 4)])
    @test_throws ErrorException Ch03Data.graph_metrics(1:3, [(1, 1)])
    @test_throws ErrorException Ch03Data.graph_metrics(1:3, [(1, 2), (2, 1)])
    @test_throws ErrorException Ch03Data.load_metrics([1.0 -1; 2 3], 2)
    @test_throws ErrorException Ch03Data.load_metrics([1.0 2], 3)
    metrics, totals = Ch03Data.load_metrics([1.0 2; 3 4], 2)
    @test totals == [3, 7]
    @test metrics["peak_total_MW"] == 7
    mktemp() do path, io
        write(io, "original")
        flush(io)
        hash = bytes2hex(sha256(read(path)))
        @test Ch03Data.verify_hash(path, hash)
        write(io, "modified")
        flush(io)
        @test_throws ErrorException Ch03Data.verify_hash(path, hash)
    end
    thesis =
        TOML.parsefile(joinpath(Ch03Data.ROOT, "docs", "reading", "ch03", "thesis-parameters.toml"))
    checked = Ch03Data.check_thesis(thesis)
    @test checked["CHP_count_conflict"]
    @test !checked["ready_for_dispatch"]
    @test checked["converters"][1]["P_max_MW_derived"] ≈ 2 / 0.95
    @test checked["heat_graph"]["radial"]
    thesis["tariff"]["end_h"][1] = 7
    @test_throws ErrorException Ch03Data.check_thesis(thesis)
end
