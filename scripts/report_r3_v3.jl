include("r3_setup.jl")
include("plot_r3_v3.jl")
length(ARGS) in (1, 2) || error("usage: report_r3_v3.jl STUDY_TOML [--follow]")
follow="--follow" in ARGS
studyfile=first(ARGS);
study=TOML.parsefile(studyfile)
oldfile="results/summaries/r3-v2/r3-v2-combined-20260917T095056-767e69d2/comparison.csv"
old=CSV.File(oldfile)
dest=joinpath("results", "summaries", "r3-v3", study["batch"]*"-"*string(uuid4())[1:8]);
mkpath(dest)
cp(studyfile, joinpath(dest, "study.toml"))
cp(joinpath(dirname(studyfile), "frozen.toml"), joinpath(dest, "frozen.toml"))
rows=NamedTuple[];
inventory=Dict{String,Any}[]
reported=Set{String}()
expected=follow ? length(TOML.parsefile(joinpath(dirname(studyfile), "frozen.toml"))["entries"]) :
         length(study["runs"])
println("OUTPUT ", dest);
flush(stdout)
while length(rows)<expected
    for e in TOML.parsefile(studyfile)["runs"]
        e["id"] in reported && continue
        println("REPORT ", e["id"])
        flush(stdout)
        dir=normpath(joinpath(dirname(studyfile), e["directory"]))
        loaded=read_r3_run(dir)
        c, r=loaded.case, loaded.result
        key=get(e, "paired_id", e["id"])
        previous=only(x for x in old if x.id==key)
        c.sha256==e["input_sha256"]==previous.input_sha256 || error("配对输入不同")
        r["initial_flow_sha256"]==e["initial_flow_sha256"] || error("初始流量不同")
        final=r["final_stage"]>0 ? r["stages"][r["final_stage"]] : nothing
        cost=isnothing(final) ? missing : final["operating_cost"]
        restoration=get(r, "physical_restoration", Dict())
        push!(
            rows,
            (
                id = e["id"],
                group = e["group"],
                input_sha256 = c.sha256,
                initial_flow_sha256 = r["initial_flow_sha256"],
                physical_pass = loaded.validation.physical_pass,
                cost,
                outer_status = r["outer_status"],
                outer_converged = r["outer_converged"],
                local_stationarity_checked = r["local_stationarity_checked"],
                cost_optimization_complete = r["cost_optimization_complete"],
                elapsed_sec = r["elapsed_sec"],
                iterations = length(r["iterations"]),
                restoration_status = get(restoration, "status", "not_needed_or_disabled"),
                restoration_accepted = count(x->x["accepted"], get(restoration, "trace", Any[])),
                v2_physical_pass = previous.physical_pass,
                v2_cost = previous.cost,
                v2_outer_status = previous.outer_status,
                cost_change = ismissing(cost)||ismissing(previous.cost) ? missing :
                              cost-previous.cost,
                physical_recovery = e["physical_recovery"],
                stationarity_check = e["stationarity_check"],
                final_objective_kind = isnothing(final) ? "none" : final["objective_kind"],
            ),
        )
        plot_r3_v3_run(dir; output = joinpath(dest, e["id"]), loaded)
        push!(
            inventory,
            Dict(
                "id"=>e["id"],
                "run_sha256"=>loaded.metadata["artifacts"]["run.toml"],
                "source_hashes"=>loaded.metadata["source_hashes"],
                "input_sha256"=>c.sha256,
            ),
        )
        CSV.write(joinpath(dest, "comparison.csv"), rows)
        open(
            io->TOML.print(io, Dict("runs"=>inventory); sorted = true),
            joinpath(dest, "provenance.toml"),
            "w",
        )
        GC.gc()
        push!(reported, e["id"])
    end
    length(rows)<expected && sleep(5)
end
cp(studyfile, joinpath(dest, "study.toml"); force = true)
open(
    io->TOML.print(
        io,
        Dict(
            "origin"=>"synthetic",
            "reoptimized"=>false,
            "prior_comparison_sha256"=>bytes2hex(sha256(read(oldfile))),
            "figures"=>["F04", "F05", "F06"],
            "runs"=>length(rows),
        );
        sorted = true,
    ),
    joinpath(dest, "figure-config.toml"),
    "w",
)
println(dest)
