using PaperRebuild, TOML
root=normpath(joinpath(@__DIR__, ".."))
dest=joinpath(root, "configs", "r4", "reconfiguration")
ispath(dest) && error("不覆盖已冻结重构输入")
mkpath(dest)
hashes=Dict{String,String}()
for (name, parent, variant) in (
    ("open", "open_flexible", "base"),
    ("import", "import_flexible", "base"),
    ("electric_bottleneck", "import_flexible", "electric"),
    ("heat_bottleneck", "import_flexible", "heat"),
    ("oracle", "import_flexible", "one_period"),
)
    old=load_r4_case(joinpath(root, "configs", "r4", "baseline", parent*".toml"))
    d=deepcopy(old.data)
    d["parent_sha256"]=old.sha256
    d["name"]="reconfiguration_"*name
    d["description"]="冻结合成重构输入；联络线阻抗/长度取原两段之和，电瓶颈1/2、热瓶颈1/4；不按优化结果调参。"
    if variant=="one_period"
        d["T"]=1
        d["grid_price"]=d["grid_price"][1:1]
        for a in d["actors"], k in ("P_load", "H_load", "PV_profile", "P_preferred", "H_preferred")
            a[k]=a[k][1:1]
        end
    end
    es=d["electric"]["edges"]
    hs=d["heat"]["pipes"]
    tie=deepcopy(es[1])
    tie["from"]=1
    tie["to"]=3
    tie["r"]=sum(x["r"] for x in es)
    tie["x"]=sum(x["x"] for x in es)
    push!(es, tie)
    pipe=deepcopy(hs[1])
    pipe["from"]=1
    pipe["to"]=3
    pipe["length_m"]=sum(x["length_m"] for x in hs)
    push!(hs, pipe)
    if variant=="electric"
        es[1]["P_max"]*=0.5
        es[1]["Q_max"]*=0.5
        es[1]["ell_max"]*=0.25
    elseif variant=="heat"
        hs[2]["H_max"]*=0.25
        hs[2]["flow_max"]*=0.25
    end
    rev=deepcopy(hs)
    for p in rev
        p["from"], p["to"]=p["to"], p["from"]
    end
    append!(hs, rev)
    d["network_control"]=Dict(
        "version"=>"r4_reconfiguration_checked_v1",
        "electric_initial"=>[1, 1, 0],
        "heat_initial"=>[1, 1, 0],
        "dwell_steps"=>2,
        "stable_history_steps"=>1,
        "max_electric_actions"=>2,
        "electric_action_cost"=>0.05,
        "heat_action_cost"=>0.1,
        "initial_condition"=>"all switches unchanged for at least one preceding time step",
        "terminal_condition"=>"free terminal topology; all initial changes charged; no cyclic operation claim",
    )
    c=R4Case(d)
    write(joinpath(dest, name*".toml"), c.source_text)
    hashes[name]=c.sha256
end
study=Dict(
    "schema"=>"r4-reconfiguration-study-v1",
    "origin"=>"synthetic",
    "cases"=>["open", "import", "electric_bottleneck", "heat_bottleneck"],
    "policies"=>["fixed", "electric", "heat", "joint"],
    "electric_models"=>["socp", "exact"],
    "budget_sec"=>600.0,
    "input_sha256"=>hashes,
    "oracle"=>"oracle",
    "oracle_scope"=>"all 72 one-period tree/direction/battery choices; continuous SOCP per choice",
    "cost_rule"=>"resource+dissatisfaction+external+physical switching cost; internal payments cancel",
    "direction_rule"=>"bidirectional heat arcs, one active direction per open physical pipe; daily valve",
    "acceptance"=>"unchanged A1, A2 relative gap and same-model cost difference <= 1e-4",
)
write(joinpath(dest, "study.toml"), PaperRebuild.r4_text(study))
println("Frozen five synthetic inputs and 32 central runs plus independent one-period oracle.")
