include("r3_setup.jl")
using CSV
studyfile=joinpath("results", "runs", "r3-v2-combined-20260917T095056", "study.toml")
study=TOML.parsefile(studyfile)
root=joinpath("results", "runs", "r3-v3-audit-"*Dates.format(now(UTC), "yyyymmddTHHMMSS"))
mkdir(root)
csvdict(path, rows) =
    isempty(rows) ? write(path, "") :
    CSV.write(
        path,
        [
            (;
                (
                    Symbol(k)=>get(r, k, missing) for
                    k in sort!(unique(vcat(collect.(keys.(rows))...)))
                )...
            ) for r in rows
        ],
    )
failure=only(filter(e->e["id"]=="two-source-VF_CT-pg", study["runs"]))
reference=only(filter(e->e["id"]=="two-source-VF_CT-reference", study["runs"]))
println("READ failure");
flush(stdout)
f=read_r3_run(normpath(joinpath(dirname(studyfile), failure["directory"])))
ref=read_r3_run(normpath(joinpath(dirname(studyfile), reference["directory"])))
audit=audit_r3_failure(f; reference = ref)
open(io->TOML.print(io, audit; sorted = true), joinpath(root, "failure.toml"), "w")
open(io->TOML.print(io, f.case.data; sorted = true), joinpath(root, "case.toml"), "w")
csvdict(joinpath(root, "electrical.csv"), audit["electrical"])
for e in study["runs"]
    (
        e["group"]=="robustness" ||
        (get(e, "method", "")=="pg" && startswith(get(e, "mode", ""), "VF"))
    ) || continue
    println("STOP ", e["id"])
    flush(stdout)
    loaded=e["id"]==failure["id"] ? f :
           read_r3_run(normpath(joinpath(dirname(studyfile), e["directory"])))
    csvdict(
        joinpath(root, e["id"]*"-stopping.csv"),
        r3_stopping_evidence(loaded.case, loaded.result),
    )
end
println(root)
