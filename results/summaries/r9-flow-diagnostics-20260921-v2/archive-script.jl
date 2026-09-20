# 封存/只读核验五项开发探针；不求解、不将日志里的迭代点当作科学候选。
using TOML, SHA, CSV, Test

const r9_diagnostic_root = normpath(joinpath(@__DIR__, ".."))
const r9_probe_ids = [
    "r9-flow-probe-vf-vt-physical-v1",
    "r9-flow-probe-vf-vt-local-v1",
    "r9-flow-probe-vf-vt-local-v2",
    "r9-flow-probe-vf-vt-local-v3",
    "r9-flow-probe-vf-vt-local-minimal-v1",
]
r9_probe_hash(p) = bytes2hex(sha256(read(p)))
r9_probe_toml(p, x) = open(io -> TOML.print(io, x; sorted = true), p, "w")

function r9_probe_path(root, relative)
    isabspath(relative) && error("Expected relative artifact path")
    path = normpath(joinpath(root, relative))
    prefix = replace(abspath(root), '\\'=>'/')*"/"
    startswith(replace(abspath(path), '\\'=>'/'), prefix) || error("Artifact path escapes root")
    return path
end

function r9_probe_row(folder, id)
    m = TOML.parsefile(joinpath(folder, "manifest.toml"))
    stage = TOML.parsefile(joinpath(folder, "stage.toml"))
    evidence = TOML.parsefile(joinpath(folder, "evidence.toml"))
    text =
        isfile(joinpath(folder, "solver-local.log")) ?
        read(joinpath(folder, "solver-local.log"), String) : ""
    last_primal = NaN
    last_iteration = 0
    for line in split(text, '\n')
        hit = match(
            r"^\s*(\d+)\s+[-+0-9.eE]+\s+([-+0-9.eE]+)\s+[-+0-9.eE]+\s+[-+0-9.eE]+\s+[-+0-9.eE]+\s+\d+s",
            line,
        )
        isnothing(hit) && continue
        last_iteration = parse(Int, hit.captures[1])
        last_primal = parse(Float64, hit.captures[2])
    end
    return (;
        id,
        solver_policy = get(m, "solver_policy", "legacy_optimizer_default"),
        representation = get(m, "physical_cone_representation", "keep"),
        termination = stage["termination"],
        primal = stage["primal"],
        elapsed_sec = evidence["elapsed_sec"],
        budget_sec = m["budget_sec"],
        budget_pass = evidence["budget_pass"],
        warm_start_loaded = occursin("Loaded warm-start solution", text),
        warm_start_incomplete = occursin("incomplete warm-start", text),
        warm_start_ignored = occursin("start ignored", text),
        solver_last_iteration = last_iteration,
        solver_last_primal = last_primal,
        candidate_saved = haskey(stage, "values"),
        model_pass = evidence["model_pass"],
        physical_pass = evidence["physical_pass"],
        terminal_pass = evidence["terminal_pass"],
    )
end

function r9_freeze_flow_diagnostics(out)
    ispath(out) && error("Refuse to overwrite existing evidence")
    sources = [joinpath(r9_diagnostic_root, "tmp", id) for id in r9_probe_ids]
    all(isfile(joinpath(s, "evidence.toml")) for s in sources) || error("Probe incomplete")
    mkpath(out)
    logs = Dict{String,Any}[]
    for (id, source) in zip(r9_probe_ids, sources)
        target = joinpath(out, "runs", id)
        manifest = TOML.parsefile(joinpath(source, "manifest.toml"))
        for (relative, hash) in manifest["files"]
            original = r9_probe_path(source, relative)
            r9_probe_hash(original) == hash || error("Probe source changed before archival")
            destination = r9_probe_path(target, relative)
            mkpath(dirname(destination))
            cp(original, destination)
        end
        for name in (
            "manifest.toml",
            "stage.toml",
            "evidence.toml",
            "native-start-audit.toml",
            "implied-cones.toml",
            "initial-raw-residuals.csv",
            "residuals.csv",
        )
            original=joinpath(source, name)
            isfile(original) && cp(original, joinpath(target, name))
        end
        original = joinpath(source, "solver-local.log")
        if isfile(original)
            clean = replace(
                read(original, String),
                r9_diagnostic_root=>"<workspace>",
                replace(r9_diagnostic_root, '\\'=>'/')=>"<workspace>",
            )
            # 原日志保持本地；公开副本仅隐去主机路径和许可标识。
            clean = replace(
                clean,
                r"(?m)^.*(?:LicenseID|Academic license|Set parameter Username).*$"=>"[local license metadata omitted]",
            )
            write(joinpath(target, "solver-local.log"), clean)
            push!(
                logs,
                Dict(
                    "id"=>id,
                    "original_sha256"=>r9_probe_hash(original),
                    "public_sha256"=>r9_probe_hash(joinpath(target, "solver-local.log")),
                    "transformation"=>"workspace paths and license metadata redacted only",
                ),
            )
        end
    end
    rows = [r9_probe_row(joinpath(out, "runs", id), id) for id in r9_probe_ids]
    CSV.write(joinpath(out, "probes.csv"), rows)
    cp(@__FILE__, joinpath(out, "archive-script.jl"))
    r9_probe_toml(
        joinpath(out, "index.toml"),
        Dict(
            "schema"=>"r9-flow-diagnostics-v1",
            "probe_ids"=>r9_probe_ids,
            "origin"=>"synthetic",
            "uses_projected_gradient"=>false,
            "input_sha256"=>"d514c3c2e94f962feb65717da43920559b4bcbca8613d2abcef2e1ed292d51b0",
            "scope"=>"development diagnostics; no accepted variable-flow schedule",
            "log_redactions"=>logs,
        ),
    )
    write(
        joinpath(out, "README.md"),
        """
# R9 continuous-flow development diagnostics

Five frozen probes use the same synthetic 44/38-node, 24-hour input and an explicitly
declared CF-CT physical witness as the initial point of an independent direct reference.
No probe returned an accepted solution. These are not projected-gradient results,
infeasibility proofs, cost-saving measurements, or a completed four-mode comparison.

Each original manifest and its listed input/source files are preserved byte for byte.
Solver logs are public copies with workspace paths and license metadata removed;
index.toml retains original and public hashes. Original local logs are unchanged.
Solver iteration residuals have the solver's own scaling and are not independent A1 checks.

Recheck without Gurobi or the private thesis:
`julia +1.12.6 --startup-file=no --project=. scripts/r9_flow_diagnostics.jl check PATH`
""",
    )
    hashes=Dict{String,String}()
    for (dir, _, names) in walkdir(out), name in names
        p=joinpath(dir, name)
        hashes[replace(relpath(p, out), '\\'=>'/')]=r9_probe_hash(p)
    end
    r9_probe_toml(joinpath(out, "artifact-hashes.toml"), Dict("files"=>hashes))
    println("Archived $(length(rows)) development probes with $(length(hashes)) files")
end

function r9_check_flow_diagnostics(out)
    index=TOML.parsefile(joinpath(out, "index.toml"))
    @test index["schema"] == "r9-flow-diagnostics-v1"
    @test !index["uses_projected_gradient"] && index["origin"] == "synthetic"
    @test index["probe_ids"] == r9_probe_ids
    for (relative, hash) in TOML.parsefile(joinpath(out, "artifact-hashes.toml"))["files"]
        @test r9_probe_hash(r9_probe_path(out, relative)) == hash
    end
    reference_sources=Dict{String,String}()
    for id in index["probe_ids"]
        dir=joinpath(out, "runs", id)
        manifest=TOML.parsefile(joinpath(dir, "manifest.toml"))
        stage=TOML.parsefile(joinpath(dir, "stage.toml"))
        evidence=TOML.parsefile(joinpath(dir, "evidence.toml"))
        @test manifest["mode"] == "VF_VT" && manifest["physical_model"]
        @test manifest["budget_sec"] == 120
        @test !manifest["uses_projected_gradient"]
        @test manifest["terminal_interpretation"] == "literal"
        @test manifest["files"]["case.toml"] == index["input_sha256"]
        for (relative, hash) in manifest["files"]
            @test r9_probe_hash(r9_probe_path(dir, relative)) == hash
        end
        for path in manifest["science_files"]
            hash=manifest["files"]["code/"*path]
            @test get!(reference_sources, path, hash) == hash
        end
        @test stage["input_sha256"] == index["input_sha256"]
        @test !haskey(stage, "values") && stage["primal"] == "NO_SOLUTION"
        @test !(evidence["model_pass"] || evidence["physical_pass"] || evidence["terminal_pass"])
        @test evidence["elapsed_sec"] <= manifest["budget_sec"] && evidence["budget_pass"]
        row=r9_probe_row(dir, id)
        @test row.warm_start_loaded == get(stage, "warm_start_confirmed_by_log", false)
        if isfile(joinpath(dir, "native-start-audit.toml"))
            s=TOML.parsefile(joinpath(dir, "native-start-audit.toml"))
            @test s["all_finite"] && s["original_point_unchanged"]
            @test s["native_count"] ==
                  s["original_count"]+s["fixed_auxiliary_count"]+s["linear_auxiliary_count"]
            @test row.warm_start_loaded
        end
        if isfile(joinpath(dir, "implied-cones.toml"))
            p=TOML.parsefile(joinpath(dir, "implied-cones.toml"))
            @test p["counts"] == Dict("3-12"=>1032, "3-26"=>1776)
            @test p["pressure_roundoff_bound_kPa"] <= 1e-10
            @test row.representation == "drop_implied_cones"
        end
    end
    io=IOBuffer()
    CSV.write(io, [r9_probe_row(joinpath(out, "runs", id), id) for id in index["probe_ids"]])
    @test String(take!(io)) == read(joinpath(out, "probes.csv"), String)
    for entry in index["log_redactions"]
        @test r9_probe_hash(joinpath(out, "runs", entry["id"], "solver-local.log")) ==
              entry["public_sha256"]
    end
end

length(ARGS)==2 || error("usage: r9_flow_diagnostics.jl freeze|check OUTPUT")
action, out=ARGS[1], abspath(ARGS[2])
if action=="freeze"
    r9_freeze_flow_diagnostics(out)
elseif action!="check"
    error("Unknown action")
end
@testset "R9 frozen flow-probe provenance and negative-result boundaries" begin
    r9_check_flow_diagnostics(out)
end
