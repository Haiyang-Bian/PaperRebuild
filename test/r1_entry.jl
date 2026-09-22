using Test, TOML
include(joinpath(@__DIR__, "..", "scripts", "r1_task.jl"))

@testset "R1 task selects its newest record, including failure" begin
    mktempdir() do root
        @test_throws ErrorException latest_r1_run(root)
        function record(
            name,
            stamp;
            scope = "ch02 fixed-flow two-node subset",
            status = "solver_optimal",
        )
            dir = joinpath(root, name)
            mkdir(dir)
            open(joinpath(dir, "metadata.toml"), "w") do io
                TOML.print(io, Dict("scope" => scope, "created_utc" => stamp))
            end
            open(joinpath(dir, "solution.toml"), "w") do io
                TOML.print(io, Dict("status" => status))
            end
            dir
        end
        older = record("r1-z-old", "2026-09-16T01:00:00")
        @test latest_r1_run(root) == older
        failed = record("r1-a-new", "2026-09-22T01:00:00"; status = "infeasible")
        @test latest_r1_run(root) == failed
        record("r9-later", "2026-09-23T01:00:00"; scope = "different chapter")
        @test latest_r1_run(root) == failed
        mkdir(joinpath(root, "unrelated-incomplete"))
        @test latest_r1_run(root) == failed
        # 同一时间用路径确定性排序；不修改元数据或以成功状态筛选。
        tie = record("r1-b-tie", "2026-09-22T01:00:00")
        @test latest_r1_run(root) == tie
        bad = record("r1-bad", "2026-09-24T01:00:00"; scope = "different chapter")
        @test_throws ErrorException latest_r1_run(root)
        write(joinpath(bad, "metadata.toml"), "not valid = [")
        @test_throws Base.TOML.ParserError latest_r1_run(root)
    end
end
