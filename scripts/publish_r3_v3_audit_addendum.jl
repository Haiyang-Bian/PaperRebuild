include("r3_setup.jl")
using CSV
target="results/summaries/r3-v3/audit-addendum-v1"
ispath(target) && error("不覆盖已有补充证据")
mkpath(target)
sources=Dict(
    "conflict.toml"=>"results/runs/r3-v3-conflict-20260917T112737/conflict.toml",
    "electric-counterexample.toml"=>"results/runs/r3-v3-electric-20260917T113726/counterexample.toml",
)
for (name, source) in sources
    cp(source, joinpath(target, name))
end
rows=NamedTuple[]
for file in sort(readdir("results/summaries/r3-v3/audit"))
    endswith(file, "-stopping.csv") || continue
    table=CSV.File(joinpath("results/summaries/r3-v3/audit", file))
    for epsilon in (1e-6, 1e-4, 1e-2)
        key=Symbol("paper_form_epsilon_"*string(epsilon))
        hits=key in propertynames(table) ?
             [r.iteration for r in table if coalesce(getproperty(r, key), false)] : Int[]
        push!(
            rows,
            (
                id = replace(file, "-stopping.csv"=>""),
                absolute_epsilon_currency = epsilon,
                first_diagnostic_hit = isempty(hits) ? missing : first(hits),
                hit_count = length(hits),
                original_outer_status = last(table).original_outer_status,
                old_pg_stop_any = any(coalesce(r.old_pg_stop, false) for r in table),
                old_local_stop_any = any(coalesce(r.old_local_stop, false) for r in table),
                author_epsilon_confirmed = false,
            ),
        )
    end
end
CSV.write(joinpath(target, "stopping-threshold-audit.csv"), rows)
files=Dict(file=>bytes2hex(sha256(read(joinpath(target, file)))) for file in readdir(target))
open(
    io->TOML.print(
        io,
        Dict("files"=>files, "sources"=>sources, "scope"=>"frozen_v2_failure_audit_only");
        sorted = true,
    ),
    joinpath(target, "manifest.toml"),
    "w",
)
println(target)
