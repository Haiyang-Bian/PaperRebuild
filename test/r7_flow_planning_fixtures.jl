using PaperRebuild, TOML

function joint_test_case(;
    free_normal = false,
    free_recovery = false,
    limit = 0.4,
    healthy_only = false,
    substeps = 1,
    UA = 0.0,
    thermal = :lossless,
    battery_rule = "paper_sum_bound",
)
    root=normpath(joinpath(@__DIR__, ".."))
    d=TOML.parsefile(joinpath(root, "configs/r7/normal-reserve-hand.toml"))
    healthy_only&&(d["electric"]["fault_budget"]=0)
    d["battery_rule"]=battery_rule
    for p in d["heat"]["pipes"]
        p["UA_S_W_K"], p["UA_R_W_K"]=UA, UA
    end
    rules=TOML.parsefile(joinpath(root, "configs/r7/planning-reserve-hand.toml"))
    foreach(e->e["loss_limit_MWh"]=limit, rules["events"])
    c=R7PlanningCase(R7NormalCase(d), rules)
    f=Dict("pipe"=>fill(5.0, 1, 4), "source"=>[5.0 5 5 5; 0 0 0 0], "load"=>[0.0 0 0 0; 5 5 5 5])
    nb=Dict{Symbol,Any}()
    for (kind, x) in f
        nb[Symbol(kind*"_min")]=free_normal ? map(y->y>0 ? 0.05 : 0.0, x) : x
        nb[Symbol(kind*"_max")]=free_normal ? map(y->y>0 ? 10.0 : 0.0, x) : x
    end
    ns=r7_normal_flow_spec(c.normal; nb..., thermal)
    rb=Dict{String,Any}()
    for pair in PaperRebuild.r7_planning_pairs(c)
        T=rules["events"][pair.event]["periods"]
        flux=any(==(1), pair.fault) ? 0.0 : 5.0
        base=Dict(
            "pipe"=>fill(flux, 1, T),
            "source"=>vcat(fill(flux, 1, T), zeros(1, T)),
            "load"=>vcat(zeros(1, T), fill(flux, 1, T)),
        )
        b=Dict{String,Any}()
        for (kind, x) in base
            cap=kind=="pipe" ? fill(10.0, 1, T) :
                kind=="source" ? vcat(fill(10.0, 1, T), zeros(1, T)) :
                vcat(zeros(1, T), fill(10.0, 1, T))
            b[kind*"_min"]=free_recovery ? zero.(cap) : x
            b[kind*"_max"]=free_recovery ? cap : x
        end
        rb[PaperRebuild.r7_planning_pair_key(pair)]=b
    end
    c, r7_flow_planning_spec(c; normal_flow = ns, recovery_bounds = rb, substeps)
end
