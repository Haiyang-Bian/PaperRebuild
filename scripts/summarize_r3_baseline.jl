using CSV, TOML, Statistics
length(ARGS)==1 || error("usage: summarize_r3_baseline.jl REPORT_DIRECTORY")
dir=only(ARGS)
rows=collect(CSV.File(joinpath(dir, "comparison.csv")))
candidates=collect(CSV.File(joinpath(dir, "candidates.csv")))
stages=collect(CSV.File(joinpath(dir, "F04-stages.csv")))
groups=Dict{String,Any}[]
for name in ("all", "initialization", "boundary", "step", "reference")
    r=name=="all" ? rows : filter(x->x.group==name, rows)
    push!(
        groups,
        Dict(
            "group"=>name,
            "count"=>length(r),
            "physical_pass"=>count(x.physical_pass for x in r),
            "model_candidate"=>count(isfinite(x.model_cost) for x in r),
            "strict_success"=>count(x.strict_redispatch_success for x in r),
            "selected_cost_complete"=>count(x.cost_optimization_complete for x in r),
            "outer_converged"=>count(x.outer_converged for x in r),
            "statuses"=>Dict(
                s=>count(x.outer_status==s for x in r) for s in unique(x.outer_status for x in r)
            ),
        ),
    )
end
eps=Dict{String,Any}[]
for ep in ("1.0e-6", "0.0001", "0.01")
    selected=filter(
        x->x.method=="baseline" && getproperty(x, Symbol("epsilon_"*ep*"_first_update"))>=0,
        rows,
    )
    relevant=filter(x->occursin("epsilon_"*ep, x.roles), candidates)
    push!(
        eps,
        Dict(
            "epsilon"=>ep,
            "hit_runs"=>length(selected),
            "strict_physical_pass"=>count(x.strict_physical_pass for x in relevant),
            "max_remaining_model_improvement"=>maximum(
                (x.model_cost-only(r.model_cost for r in rows if r.id==x.id) for x in relevant);
                init = 0.0,
            ),
            "first_updates"=>Dict(
                x.id=>getproperty(x, Symbol("epsilon_"*ep*"_first_update")) for x in selected
            ),
        ),
    )
end
open(joinpath(dir, "findings.toml"), "w") do io
    TOML.print(io, Dict("groups"=>groups, "epsilon"=>eps); sorted = true)
end
for g in groups
    println(g)
end
for name in ("single-source", "two-source")
    println("\n", name)
    for r in rows
        r.case_group==name || continue
        terminal=filter(s->s.id==r.id && s.stage==r.selected_stage, stages)
        term=isempty(terminal) ? "none" :
             string(only(terminal).terminal_checked, "/", only(terminal).terminal_pass)
        println(
            r.id,
            " | initial ",
            r.initial_model_pass,
            " diag ",
            r.initial_diagnostic,
            " | updates ",
            r.accepted_updates,
            " model ",
            r.model_cost,
            " phys ",
            r.physical_cost,
            " | core/tail ",
            r.core_cost,
            "/",
            r.tail_cost,
            " | terminal ",
            term,
            " | ",
            r.outer_status,
        )
    end
end
for e in eps
    println(e)
end
