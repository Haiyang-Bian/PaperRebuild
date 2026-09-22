using PaperRebuild, TOML, SHA

function main()
    root=normpath(joinpath(@__DIR__, ".."))
    names=["inner-tie-two-hour", "inner-tie-bottleneck", "inner-tie-two-fault"]
    files=[joinpath(root, "configs/r7", n*".toml") for n in names]
    marker=joinpath(root, "configs/r7/inner-freeze.toml")
    any(ispath, vcat(files, [marker])) && error("不覆盖已冻结故障案例")
    base=TOML.parsefile(joinpath(root, "configs/r7/recovery-hand.toml"))
    d=deepcopy(base)
    d["name"]="synthetic_three_node_tie_two_hour"
    d["preplan_id"]="synthetic-explicit-two-hour-state-not-optimized-normal-plan"
    d["periods"]=2
    d["loss_limit_MWh"]=0.0
    e=d["electric"]
    e["nodes"]=3
    e["flow_domain"]="signed"
    e["root_eligible"]=[1, 1, 0]
    e["tan_phi"]=[0.0, 0.0, 0.0]
    e["shed_fraction_max"]=[1.0, 1.0, 1.0]
    e["load_MW"]=[[0.0, 0.0], [0.3, 0.3], [0.3, 0.3]]
    line=deepcopy(e["lines"][1])
    e["lines"]=[
        merge(deepcopy(line), Dict("from"=>i, "to"=>j, "base_closed"=>z)) for
        (i, j, z) in ((1, 2, 1), (2, 3, 1), (1, 3, 0))
    ]
    h=d["heat"]
    h["ambient_K"]=[293.15, 293.15]
    h["reference_flow_kg_s"]=[5.0, 5.0]
    h["load_MW"]=[[0.0, 0.0], [0.4, 0.4]]
    h["pipes"][1]["normal_flow_kg_s"]=[5.0, 5.0]
    chp=d["devices"][1]
    chp["commitment"]=[1, 1]
    chp["P_min_MW"]=0.2
    chp["previous_P_MW"]=[0.4]
    bes=d["devices"][2]
    bes["initial_MWh"]=[0.4]
    bes["E_max_MWh"]=0.5
    cases=[deepcopy(d) for _ in names]
    cases[2]["name"]="synthetic_three_node_tie_bottleneck"
    foreach(l->l["P_max_MW"]=0.3, cases[2]["electric"]["lines"])
    cases[3]["name"]="synthetic_three_node_two_faults"
    cases[3]["electric"]["fault_budget"]=2
    foreach(R7RecoveryCase, cases)
    rules=Dict(
        "schema"=>"r7-inner-case-freeze-v1",
        "origin"=>"synthetic",
        "created_before_optimization"=>true,
        "budget_per_method_sec"=>600,
        "scope"=>"fixed inherited state; three electric nodes, three lines, two hours; not thesis-scale",
        "expected"=>Dict(names[1]=>0.0, names[2]=>0.2, names[3]=>Inf),
        "derivation"=>[
            "单故障通过闭合1-3联络线维持含根森林；闭合故障对应自动断开不计主动动作。1-2断线需要2-3反向功率。",
            "每小时CHP0.4MW+电池0.2MW满足总电负荷0.6MW，CHP热0.4MW，电池两小时共0.4MWh。",
            "瓶颈配置所有电线容量预设0.3MW，健康基态或1-2故障时CHP可送≤0.3MW，加电池≤0.2MW，至少失供0.1MW/小时。供热缺口共0.2MWh小于初始水箱可用显热7/30MWh；达到下界仍需全模型验证。",
            "两故障允许1-2及1-3同时断开：CHP孤岛无电力消纳且继承开机P≥0.2MW，完整恢复不可行。",
        ],
        "files"=>Dict{String,String}(),
    )
    for (path, data) in zip(files, cases)
        write(path, PaperRebuild.r7_text(data))
        rules["files"][replace(relpath(path, root), '\\'=>'/')]=bytes2hex(sha256(read(path)))
    end
    write(marker, PaperRebuild.r7_text(rules))
    println("Frozen three synthetic inputs and analytic expectations before optimization.")
end
main()
