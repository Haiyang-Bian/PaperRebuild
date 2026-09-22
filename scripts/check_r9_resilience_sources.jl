# 原页转录与单位核查；无需优化或商业许可，旧冻结台账不迁移。
using TOML, Test
root=dirname(@__DIR__)
d=TOML.parsefile(joinpath(root, "docs/reading/ch07/inputs.toml"))
r=TOML.parsefile(joinpath(root, "docs/reading/ch07/resilience-review.toml"))
old=TOML.parsefile(joinpath(root, "results/summaries/r9-inputs-20260920-v1/inputs.toml"))
find(id) = only(filter(x->x["id"]==id, r["finding"]))
@testset "R9 resilience source correction and unresolved input separation" begin
    @test r["source_sha256"]==d["source_sha256"]==old["source_sha256"]
    @test !r["optimization_performed"] && !r["original_input_complete"]
    @test r["pdf_pages"]==collect(138:143)
    correction=find("R9-RS01")
    gt=only(d["resilience"]["gt"])
    @test correction["prior_project_CNY_MWh"]==only(old["resilience"]["gt"])["cost_CNY_MWh"]==711.3
    @test gt["cost_literal_CNY_kWh"]==correction["original_literal_CNY_kWh"]==0.7713
    @test gt["cost_CNY_MWh"]==1000gt["cost_literal_CNY_kWh"]==correction["adopted_CNY_MWh"]==771.3
    for section in ("base", "trading", "reserve", "four_modes")
        haskey(d, section) && @test d[section]==old[section]
    end
    prior_rc=deepcopy(old["resilience"])
    corrected_rc=deepcopy(d["resilience"])
    delete!(prior_rc, "gt")
    delete!(corrected_rc, "gt")
    @test corrected_rc==prior_rc
    g=find("R9-RS02")
    a=Set(g["nodes_figure_7_12"])
    b=Set(g["nodes_figure_7_14"])
    @test length(a)==12 && length(b)==13
    @test setdiff(a, b)==Set([14, 33])
    @test setdiff(b, a)==Set([17, 18, 31])
    @test all(n->1<=n<=44, union(a, b))
    f=find("R9-RS03")
    edges=Set(Tuple(sort(e)) for e in f["vulnerable_edges_figure_7_12"])
    failures=Set(Tuple(sort(e)) for e in f["event1_failed_edges"])
    @test setdiff(failures, edges)==Set([(1, 7)])
    @test (28, 29) in edges
    @test !haskey(f, "max_fault_count")
    @test find("R9-RS05")["event1_peak_interval_h"]==[13.75, 14.0]
    @test find("R9-RS07")["scheme_4C_HS"]==d["resilience"]["scheme_4C_HS_literal"]
    @test find("R9-RS07")["scheme_4C_NR"]==d["resilience"]["scheme_4C_NR_literal"]
    @test Set(["R9-Q04", "R9-Q05"]) ⊆ Set(x["id"] for x in d["gaps"])
end
