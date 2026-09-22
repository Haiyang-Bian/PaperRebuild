# 新运行只追加独立目录；Julia自编外层，不调用直接流量修正。
push!(LOAD_PATH, normpath(joinpath(@__DIR__, "..")))
include("r3_setup.jl")
using Clarabel
studyfile=joinpath(@__DIR__, "..", "configs", "r3", "pg-study.toml")
study=TOML.parsefile(studyfile)
function option(name, default)
    i=findfirst(a->startswith(a, name*"="), ARGS)
    return isnothing(i) ? default : split(ARGS[i], '='; limit = 2)[2]
end
budget=parse(Float64, option("--budget", string(study["budget_per_instance_sec"])))
iterations=parse(Int, option("--iterations", string(study["max_iterations"])))
selected=filter(a->!startswith(a, "--"), ARGS)
entries=Dict{String,Any}[]
for name in study["cases"], init in study["initializations"]
    push!(
        entries,
        Dict(
            "id"=>name*"-"*init,
            "case"=>name,
            "initialization"=>init,
            "local_halfspace"=>study["local_halfspace"],
        ),
    )
end
append!(entries, study["extra"])
all(id->any(e["id"]==id for e in entries), selected) || error("未知案例ID")
factory=nothing
if !("--open" in ARGS)
    import Gurobi
    global factory=r3_gurobi_factory(Gurobi)
end
batch="r3-pg-"*Dates.format(now(UTC), "yyyymmddTHHMMSS")*"-"*string(uuid4())[1:8]
root=joinpath(@__DIR__, "..", "results", "runs", batch)
mkdir(root)
cp(studyfile, joinpath(root, "config.toml"))
records=Dict{String,Any}[]
function checkpoint()
    open(joinpath(root, "study.toml"), "w") do io
        TOML.print(
            io,
            Dict(
                "schema"=>"r3-pg-study-v1",
                "batch"=>batch,
                "origin"=>"synthetic",
                "config_sha256"=>bytes2hex(sha256(read(studyfile))),
                "runs"=>records,
                "budget_per_instance_sec"=>budget,
                "max_iterations"=>iterations,
            );
            sorted = true,
        )
    end
end
checkpoint()
for entry in entries
    isempty(selected) || entry["id"] in selected || continue
    init=entry["initialization"]
    e=deepcopy(entry)
    startswith(init, "box") && (e["initialization"]="case_fixed")
    c, m=r3_study_case(e)
    if haskey(e, "mass_kg")
        d=deepcopy(c.data)
        d["heat"]["pipes"][1]["length_m"]=e["mass_kg"]/(
            d["heat"]["rho_kg_m3"]*d["heat"]["pipes"][1]["area_m2"]
        )
        io=IOBuffer()
        TOML.print(io, d; sorted = true)
        c=R2Case(d, bytes2hex(sha256(take!(io))))
    end
    preparation=0.0
    if startswith(init, "box")
        start=PaperRebuild.r3_clock()
        lo, hi, width=PaperRebuild.r3_flow_box(c)
        target=lo+parse(Float64, init[4:end])/100*width
        projection=PaperRebuild.r3_project(
            c,
            target,
            Clarabel.Optimizer;
            deadline = start+min(60, budget),
        )
        projection["status"]=="projected" || error("冻结初值投影失败：$(entry["id"])")
        m=PaperRebuild.r3_matrix(projection["flow"])
        preparation=PaperRebuild.r3_clock()-start
    end
    println("START ", entry["id"])
    flush(stdout)
    result=solve_r3_projected_gradient(
        c;
        optimizer = factory,
        convex_optimizer = Clarabel.Optimizer,
        initial_flow = m,
        budget_sec = max(0.001, budget-preparation),
        max_iterations = iterations,
        local_halfspace = get(entry, "local_halfspace", true),
    )
    result["initialization_kind"]=init
    result["preparation_sec"]=preparation
    result["total_elapsed_sec"]=result["elapsed_sec"]+preparation
    path=save_r3_run(c, result; root, run_id = entry["id"])
    push!(
        records,
        Dict(
            "id"=>entry["id"],
            "case"=>entry["case"],
            "initialization"=>init,
            "directory"=>basename(path),
            "outer_status"=>result["outer_status"],
            "physical_pass"=>read_r3_run(path).validation.physical_pass,
            "elapsed_sec"=>result["total_elapsed_sec"],
        ),
    )
    checkpoint()
    println("DONE ", last(records))
    flush(stdout)
end
println("STUDY ", normpath(joinpath(root, "study.toml")))
