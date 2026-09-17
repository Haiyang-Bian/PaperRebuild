using JuMP, Clarabel, TOML

@testset "R3 fixed schedule and reconstruction ch03-060" begin
    c = load_r2_case(joinpath(@__DIR__, "..", "configs", "r2", "single-source.toml"))
    original = deepcopy(c.data)
    m = reshape([1.0, 1.02, 1.0, 1.02], 1, :)
    @test build_r2_model(c; fixed_flows = true, flow_schedule = m).class == "SOCP"
    r = solve_r2_case(
        c;
        optimizer = Clarabel.Optimizer,
        fixed_flows = true,
        flow_schedule = m,
        budget_sec = 60.0,
    )
    @test validate_r2_solution(c, r).model_pass
    @test r["values"]["m_pipe"][1] ≈ vec(m)
    @test c.data == original
    @test r["input_sha256"] == c.sha256
    before = deepcopy(r)
    reconstructed = reconstruct_r3_pressure(c, r)
    @test r == before
    @test reconstructed["objective"] == r["objective"]
    @test all(reconstructed["values"][k] == v for (k, v) in r["values"] if !startswith(k, "kappa_"))
    @test all(
        x.pass for
        x in validate_r2_solution(c, reconstructed).rows if x.equation in ("3-22", "3-25", "3-26")
    )
    @test_throws ArgumentError build_r2_model(c; flow_schedule = m)
    for invalid in (zeros(1, 4), fill(NaN, 1, 4), fill(2.0, 1, 4), ones(2, 4))
        @test_throws ArgumentError build_r2_model(c; fixed_flows = true, flow_schedule = invalid)
    end
    bad = deepcopy(r)
    bad["values"]["P_grid"][1] += 1
    @test_throws ArgumentError reconstruct_r3_pressure(c, bad)
    mktempdir() do dir
        saved = save_r2_run(c, r; root = dir, run_id = "schedule")
        loaded = read_r2_run(saved)
        @test loaded.result["flow_schedule"] == r["flow_schedule"]
        @test validate_r2_solution(loaded.case, loaded.result).model_pass
    end
end
