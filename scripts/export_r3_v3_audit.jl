include("r3_setup.jl")
source="results/runs/r3-v3-audit-20260917T104953"
target="results/summaries/r3-v3/audit"
isdir(target) && error("保留已有审计摘要，请使用新版本路径")
mkpath(target)
for file in readdir(source)
    endswith(file, "-stopping.csv") && cp(joinpath(source, file), joinpath(target, file))
end
a=TOML.parsefile(joinpath(source, "failure.toml"))
for x in a["selected"]
    for key in ("sensitivity", "source_hashes_at_solve")
        pop!(x["record"], key, nothing)
    end
end
out=Dict(
    "source_run_id"=>a["source_run_id"],
    "input_sha256"=>a["input_sha256"],
    "selected"=>a["selected"],
    "reference_run_id"=>a["reference_run_id"],
    "reference_final"=>a["reference_final"],
)
open(io->TOML.print(io, out; sorted = true), joinpath(target, "failure.toml"), "w")
cp(joinpath(source, "case.toml"), joinpath(target, "case.toml"))
cp(joinpath(source, "electrical.csv"), joinpath(target, "electrical.csv"))
cp("results/runs/r3-v3-heat-bound-20260917T110643/bound.toml", joinpath(target, "heat-bound.toml"))
eq=TOML.parsefile("results/runs/r3-v3-equivalence-20260917T105739/equivalence.toml")
for x in eq["runs"]
    pop!(x["result"], "source_hashes_at_solve", nothing)
end
open(io->TOML.print(io, eq; sorted = true), joinpath(target, "equivalence.toml"), "w")
files=Dict(file=>bytes2hex(sha256(read(joinpath(target, file)))) for file in readdir(target))
open(
    io->TOML.print(io, Dict("files"=>files, "source"=>source); sorted = true),
    joinpath(target, "manifest.toml"),
    "w",
)
println(target)
