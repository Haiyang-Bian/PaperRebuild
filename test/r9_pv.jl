@testset "R9-P1:P6 44/38 periodic input and fixed-mode model" begin
    root = normpath(joinpath(@__DIR__, ".."))
    source = joinpath(root, "docs/reading/ch07")
    protocol = joinpath(root, "configs/r9/pv-protocol.toml")
    c = r9_pv_case(source, protocol)
    check = audit_r9_pv_input(c)
    @test check.pass
    @test c.sha256 == r9_pv_case(source, protocol).sha256
    @test length(c.data["electric"]["nodes"]) == 44
    @test length(c.data["heat"]["pipes"]) == 37
    @test c.data["T"] == 24
    @test check.source_MWh ≈ check.load_MWh+check.loss_MWh atol=1e-7
    @test check.loss_MWh > 0
    @test maximum(sum(n["P_MW"][t] for n in c.data["electric"]["nodes"]) for t in 1:24) ≈ 45.67*0.9
    @test sum(g["P_max"] for g in c.data["devices"] if g["kind"] == "PV") == 12.0
    @test c.data["devices"][2]["P_max"] ≈ 1/0.92
    @test any(length(unique(p["R_history_K"])) > 1 for p in c.data["heat"]["pipes"])
    b = build_r9_pv_model(c)
    @test b.class == "SOCP"
    @test !JuMP.has_values(b.model)
    @test length(b.constraints["R9-P6"]) == 74
    @test_throws ErrorException build_r9_pv_model(c; mode = :VF_VT)
    @test_throws ErrorException solve_r9_pv_case(c; budget_sec = 601)
    stopped = solve_r9_pv_case(c; budget_sec = 0)
    @test stopped["status"] == "time_limit_no_solution"
    @test !validate_r9_pv_solution(c, stopped).model_pass
    mktempdir() do dir
        path = joinpath(dir, "case.toml")
        write(path, PaperRebuild.r9_text(c.data))
        @test load_r9_pv_case(path).sha256 == c.sha256
        bad = deepcopy(c.data)
        bad["r9"]["protocol"]["heat_profile"][1] = 0.1
        write(path, PaperRebuild.r9_text(bad))
        @test_throws ErrorException load_r9_pv_case(path)
        bad = deepcopy(c.data)
        bad["heat"]["pipes"][1]["R_history_K"][end] += 0.1
        write(path, PaperRebuild.r9_text(bad))
        @test_throws ErrorException load_r9_pv_case(path)
    end
end
