# 只读冻结输入与原值；用归档包装重放报告，不重新求解。
using Test, TOML, CSV, SHA
include("r9_numerics_study.jl")

function check_r9_numerics_results(batch, report)
    saved = TOML.parsefile(joinpath(report, "report.toml"))
    hashfile = R9NumericsStudy.hashfile
    @testset "R9 anchored original values, full terminal basis and tamper rejection" begin
        @test saved["schema"] == "r9-numerics-report-v1"
        @test saved["source_batch"] == basename(abspath(batch))
        @test saved["manifest_sha256"] == hashfile(joinpath(batch, "manifest.toml"))
        for (p, h) in saved["files"]
            @test hashfile(joinpath(report, p)) == h
        end
        loader = Module(gensym(:R9NumericsReplay))
        Base.include(loader, joinpath(batch, "numerics-study-source.jl"))
        api = Base.invokelatest(() -> getfield(loader, :R9NumericsStudy))
        f = Base.invokelatest(() -> getfield(api, :frozen)(batch))
        @test f.c.sha256 == saved["input_sha256"]
        mktempdir() do dir
            fresh = joinpath(dir, "replay")
            Base.invokelatest(() -> getfield(api, :report)(batch, fresh))
            for p in keys(saved["files"])
                @test read(joinpath(report, p)) == read(joinpath(fresh, p))
            end
        end
        summary = collect(CSV.File(joinpath(report, "summary.csv")))
        @test length(summary) == length(f.manifest["entries"]) == 6
        for entry in f.manifest["entries"]
            folder = joinpath(batch, "runs", entry["id"])
            started = TOML.parsefile(joinpath(folder, "started.toml"))
            r = TOML.parsefile(joinpath(folder, "result.toml"))
            row = only(x for x in summary if x.run_id == entry["id"])
            @test started["entry"] == entry
            @test started["manifest_sha256"] == saved["manifest_sha256"]
            @test r["input_sha256"] == f.c.sha256
            @test r["mode"] == entry["mode"] && r["physical_model"] == entry["physical"]
            @test r["origin"] == "synthetic" && r["terminal_interpretation"] == "reference_anchored"
            @test r["elapsed_sec"] <= r["budget_sec"] + 0.1
            b = Base.invokelatest(
                () -> getfield(f.mod, :build_r9_reduced_model)(
                    f.c;
                    mode = Symbol(entry["mode"]),
                    physical = entry["physical"],
                    terminal = :reference_anchored,
                ),
            )
            # 完整重建证书，检查基底、位移、秩和误差界，不只相信记录的通过标志。
            @test b.terminal_certificate == r["terminal_certificate"]
            constant_rows =
                [Dict(string(k)=>getproperty(x, k) for k in keys(x)) for x in b.constant_checks]
            expected_hash =
                Base.invokelatest(() -> getfield(f.mod, :r9_hash)(Dict("rows"=>constant_rows)))
            @test expected_hash == r["representation_certificate"]["constant_checks_sha256"]
            @test all(x.pass for x in b.constant_checks)
            @test row.model_pass && row.physical_pass && row.terminal_pass
            @test row.adopted_terminal_pass && row.daily_energy_pass
            s = r["stage"]
            @test row.cost_CNY == s["operating_cost"]
            @test haskey(s, "solver_bound") && isfinite(s["solver_bound"])
            @test -1e-4 <=
                  (s["solver_objective"]-s["solver_bound"])/max(1, abs(s["solver_objective"])) <=
                  1e-4
            bad = deepcopy(r)
            bad["stage"]["values"]["tau_R_in"][1][end] += 0.1
            v = Base.invokelatest(
                () -> getfield(f.mod, :validate_r9_reduced_solution)(
                    f.c,
                    bad;
                    check_representation = false,
                ),
            )
            @test !v.terminal_pass && !v.physical_pass
            if entry["mode"] == "CF_VT"
                @test r["terminal_certificate"]["rank_exact_binary"] == 32
                @test r["terminal_certificate"]["free_source_count"] == 16
                bad = deepcopy(r)
                bad["stage"]["values"]["r9_terminal_coordinates"][1] += 0.1
                v = Base.invokelatest(
                    () -> getfield(f.mod, :validate_r9_reduced_solution)(
                        f.c,
                        bad;
                        check_representation = false,
                    ),
                )
                @test !v.adopted_terminal_pass
                bad = deepcopy(r)
                bad["terminal_certificate"]["terminal_matrix"][1][1] += 0.01
                @test_throws ArgumentError Base.invokelatest(
                    () -> getfield(f.mod, :validate_r9_reduced_solution)(f.c, bad),
                )
                bad = deepcopy(r)
                bad["terminal_certificate"]["basis"][1][1] = NaN
                @test_throws ArgumentError Base.invokelatest(
                    () -> getfield(f.mod, :validate_r9_reduced_solution)(
                        f.c,
                        bad;
                        check_representation = false,
                    ),
                )
            end
        end
        for mode in ("CF_CT", "CF_VT")
            a = only(r for r in summary if r.mode == mode && r.solver == "Clarabel")
            b = only(
                r for r in summary if r.mode == mode && r.solver == "Gurobi" && !r.physical_model
            )
            @test abs(a.cost_CNY-b.cost_CNY)/max(1, abs(a.cost_CNY), abs(b.cost_CNY)) <= 1e-4
        end
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    length(ARGS) == 2 || error("usage: check_r9_numerics_results.jl BATCH REPORT")
    check_r9_numerics_results(abspath.(ARGS)...)
end
