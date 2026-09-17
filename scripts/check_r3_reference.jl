# 同一个固定流量连续SOCP用开放/商业求解器交叉核验，结果与界按A2判定。
push!(LOAD_PATH, normpath(joinpath(@__DIR__, "..")))
using Test, Clarabel
include("r3_setup.jl")
import Gurobi
factory=r3_gurobi_factory(Gurobi)
c, m=r3_study_case(Dict("case"=>"single-source", "initialization"=>"case_fixed"))
batch="r3-reference-"*Dates.format(now(UTC), "yyyymmddTHHMMSS")*"-"*string(uuid4())[1:8]
target=joinpath(@__DIR__, "..", "results", "runs", batch)
mkpath(target)
results=Dict{String,Any}()
for (name, optimizer) in (("clarabel", Clarabel.Optimizer), ("gurobi", factory))
    r=solve_r3_feasibility(
        c;
        initial_flow = m,
        optimizer = factory,
        convex_optimizer = optimizer,
        budget_sec = 60.0,
    )
    path=save_r3_run(c, r; root = target, run_id = batch*"_"*name)
    saved=read_r3_run(path)
    @test saved.validation.physical_pass
    firststage=only(filter(s->s["stage"]=="fixed_dispatch", r["stages"]))
    @test firststage["status"]=="solver_optimal"
    @test firststage["solver_relative_gap"]<=1e-4
    results[name]=Dict(
        "directory"=>basename(path),
        "cost"=>firststage["operating_cost"],
        "bound"=>firststage["solver_bound"],
        "gap"=>firststage["solver_relative_gap"],
        "flow_sha256"=>firststage["flow_sha256"],
    )
end
reference=results["clarabel"]["cost"]
difference=results["gurobi"]["cost"]-reference
relative=abs(difference)/max(1, abs(reference))
@test relative<=1e-4
@test results["clarabel"]["flow_sha256"]==results["gurobi"]["flow_sha256"]
evidence=Dict(
    "schema"=>"r3-reference-v1",
    "origin"=>"synthetic",
    "batch"=>batch,
    "input_sha256"=>c.sha256,
    "scope"=>"same fixed-flow continuous SOCP; not a global flow-optimization comparison",
    "results"=>results,
    "cost_difference"=>difference,
    "relative_difference"=>relative,
    "A2_threshold"=>1e-4,
    "A2_pass"=>relative<=1e-4,
    "assertions_passed"=>8,
)
open(io->TOML.print(io, evidence; sorted = true), joinpath(target, "reference.toml"), "w")
println("R3_REFERENCE=", joinpath(target, "reference.toml"))
println("Relative objective difference: ", relative)
