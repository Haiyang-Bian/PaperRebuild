# 已封存区域证据与图源的轻量验收；数值移位回放另由--replay执行。
using Test, CSV, TOML, SHA
include("r9_electric_cut_evidence.jl")
root = dirname(@__DIR__)
evidence = joinpath(root, "results/summaries/r9-electric-cut-evidence-20260922-v1")
figure = joinpath(root, "docs/src/assets/r9-electric-cut-v1")
hashfile(p) = bytes2hex(sha256(read(p)))
function check_manifest(dir)
    m = TOML.parsefile(joinpath(dir, "artifacts.toml"))["files"]
    actual = R9ElectricCutEvidence.files(dir)
    delete!(actual, "artifacts.toml")
    @test m == actual
    for (path, hash) in m
        @test !isabspath(path) && !occursin(':', path) && !(".." in split(path, '/'))
        @test occursin(r"^[0-9a-f]{64}$", hash)
        @test filesize(joinpath(dir, path)) <= 5 * 1024^2
    end
end
@testset "R9 regional bound, capacity origin and F50 evidence" begin
    @test R9ElectricCutEvidence.check(evidence)
    check_manifest(evidence)
    check_manifest(figure)
    rows = collect(CSV.File(joinpath(evidence, "summary.csv")))
    @test Set(r.fault for r in rows) == Set(["external_only", "single_1_2", "author_event1"])
    @test all(r -> r.certificate_pass && r.parent_model_pass, rows)
    @test all(r -> 0 <= r.lower_bound_MWh <= r.parent_loss_MWh, rows)
    event = only(filter(r -> r.fault == "author_event1", rows))
    @test event.threshold_excluded && event.lower_bound_MWh > event.limit_MWh
    @test isapprox(event.lower_bound_MWh, 6.04588006857483; atol = 1e-12)
    @test all(
        r -> !r.threshold_excluded && r.lower_bound_MWh == 0,
        filter(r -> r.fault != "author_event1", rows),
    )
    provenance = TOML.parsefile(joinpath(evidence, "provenance.toml"))
    @test all(
        p ->
            p["capacity_rule_verified"] &&
            p["maximum_capacity_error_MW"] == 0 &&
            !p["original_line_ratings_available"],
        values(provenance),
    )
    certificate = TOML.parsefile(joinpath(evidence, "certificates.toml"))["author_event1"]
    @test !certificate["original_minimum_loss_certified"] &&
          !certificate["recovery_feasibility_certified"]
    @test isempty(certificate["internal_generator_ids"]) && length(certificate["nodes"]) == 21
    fc = TOML.parsefile(joinpath(figure, "figure-config.toml"))
    @test fc["source_artifacts_sha256"] == hashfile(joinpath(evidence, "artifacts.toml"))
    @test fc["case_sha256"] == certificate["case_sha256"] && fc["run_id"] == event.parent_run_id
    @test fc["synthetic_replacement_inputs"] &&
          !fc["optimization_performed"] &&
          !fc["original_line_ratings_available"]
    data = collect(CSV.File(joinpath(figure, "source.csv")))
    source = filter(
        r -> r.fault == "author_event1",
        collect(CSV.File(joinpath(evidence, "intervals.csv"))),
    )
    rowvalues(r) = Tuple(getproperty(r, name) for name in propertynames(r))
    @test map(rowvalues, data) == map(rowvalues, source) && length(data) == 16
    @test isapprox(
        sum(r.weighted_energy_lower_MWh for r in data),
        event.lower_bound_MWh;
        atol = 1e-12,
    )
    lines = collect(CSV.File(joinpath(figure, "boundary.csv")))
    @test [r.line for r in lines] == certificate["boundary_lines"]
    case = TOML.parsefile(joinpath(evidence, "objects", fc["case_sha256"]))
    for r in lines
        original = case["electric"]["lines"][r.line]
        @test (r.from, r.to, r.capacity_MW) ==
              (original["from"], original["to"], original["P_max_MW"])
    end
    @test isapprox(sum(r.capacity_MW for r in lines), event.boundary_import_upper_MW; atol = 1e-12)
    # 先验证完整副本可读，再只改变一个文件，防止把副本不完整误作篡改检查。
    mktempdir() do scratch
        copydir = joinpath(scratch, "evidence")
        cp(evidence, copydir)
        @test R9ElectricCutEvidence.check(copydir)
        write(joinpath(copydir, "summary.csv"), "altered\n")
        @test_throws ErrorException R9ElectricCutEvidence.check(copydir)
    end
end
