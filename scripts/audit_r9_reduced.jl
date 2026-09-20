# 只读重验开发记录；原求解状态、近可行候选和费用证据分别输出。
using PaperRebuild, TOML, CSV, SHA
length(ARGS) == 2 || error("usage: audit_r9_reduced.jl RUN_DIRECTORY NEW_AUDIT_DIRECTORY")
run_dir, out = ARGS
ispath(out) && error("不覆盖已有审计")
manifest = TOML.parsefile(joinpath(run_dir, "manifest.toml"))
for (path, digest) in manifest["source_hashes"]
    bytes2hex(sha256(read(joinpath(run_dir, "code", path)))) == digest ||
        error("开发源码快照被修改")
end
c = load_r9_pv_case(joinpath(run_dir, "case.toml"))
c.sha256 == manifest["input_sha256"] || error("输入身份改变")
r = TOML.parsefile(joinpath(run_dir, "result.toml"))
diagnostic = haskey(r, "diagnostic_candidate")
candidate = diagnostic ? merge(r, Dict("stage" => r["diagnostic_candidate"]["stage"])) : r
checked = validate_r9_pv_solution(c, candidate)
rows = sort(checked.rows; by = row -> -row.residual / row.tolerance)
mkpath(out)
CSV.write(joinpath(out, "residuals.csv"), rows)
summary = Dict{String,Any}(
    "schema" => "r9-reduced-development-audit-v1",
    "input_sha256" => c.sha256,
    "source_result_sha256" => bytes2hex(sha256(read(joinpath(run_dir, "result.toml")))),
    "diagnostic_only" => diagnostic,
    "status" => r["status"],
    "model_pass" => checked.model_pass,
    "physical_pass" => checked.physical_pass,
    "terminal_pass" => checked.terminal_pass,
    "failure_count" => count(row -> !row.pass, rows),
)
if haskey(candidate["stage"], "values")
    energy = r9_daily_heat_balance(c, candidate["stage"]["values"])
    summary["daily_heat"] = Dict(string(k) => getproperty(energy, k) for k in keys(energy))
end
open(io -> TOML.print(io, summary; sorted = true), joinpath(out, "audit.toml"), "w")
println(summary)
println("Largest normalized residuals:")
foreach(println, first(rows, min(12, length(rows))))
