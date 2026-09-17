include("r3_setup.jl")
using CSV
length(ARGS)==1 || error("usage: recover_r3_v3_checkpoint.jl INTERRUPTED_BATCH_DIRECTORY")
source=only(ARGS);
cfg=TOML.parsefile(joinpath(source, "frozen.toml"));
records=Dict{String,Any}[]
target=joinpath("results", "runs", "r3-v3-checkpoint-"*Dates.format(now(UTC), "yyyymmddTHHMMSS"));
mkpath(target)
cp(joinpath(source, "frozen.toml"), joinpath(target, "frozen.toml"))
for e in cfg["entries"]
    folder=joinpath(source, e["id"])
    meta=joinpath(folder, "metadata.toml")
    isfile(meta) || continue
    md=TOML.parsefile(meta)
    for (file, hash) in md["artifacts"]
        open(joinpath(folder, file)) do io
            bytes2hex(sha256(io))==hash || error("不完整的保存快照："*e["id"]*"/"*file)
        end
    end
    header=String[]
    for line in eachline(joinpath(folder, "run.toml"))
        startswith(line, "[") && break
        push!(header, line)
    end
    r=TOML.parse(join(header, "\n"))
    table=CSV.File(joinpath(folder, "stages.csv"))
    laststage=r["final_stage"]
    push!(
        records,
        merge(
            deepcopy(e),
            Dict(
                "directory"=>replace(relpath(folder, target), '\\'=>'/'),
                "elapsed_sec"=>r["elapsed_sec"],
                "outer_status"=>r["outer_status"],
                "outer_converged"=>r["outer_converged"],
                "local_stationarity_checked"=>r["local_stationarity_checked"],
                "physical_pass"=>md["physical_pass"],
                "cost"=>laststage>0 ? table[laststage].operating_cost : NaN,
                "checkpoint_recovered_from_complete_snapshot"=>true,
            ),
        ),
    )
end
open(
    io->TOML.print(
        io,
        Dict(
            "schema"=>"r3-v3-study-v1",
            "batch"=>basename(target),
            "origin"=>"synthetic",
            "runs"=>records,
            "config_sha256"=>bytes2hex(sha256(read(joinpath(source, "frozen.toml")))),
        );
        sorted = true,
    ),
    joinpath(target, "study.toml"),
    "w",
)
open(
    io->TOML.print(
        io,
        Dict(
            "reason"=>"restoration_candidates_inherited_cost_bound_fields",
            "action"=>"interrupted_before_affected_restoration_cases; preserve_complete_snapshots; report revalidates all runs",
            "source_batch"=>source,
            "recovered_runs"=>length(records),
        );
        sorted = true,
    ),
    joinpath(target, "interruption.toml"),
    "w",
)
println(joinpath(target, "study.toml"))
