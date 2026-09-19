using TOML, SHA

# 明确的新合成解析例：不是修改旧normal-hand，也不根据求解结果选参数。
root=normpath(joinpath(@__DIR__, ".."))
paths=[
    joinpath(root, "configs/r7", p) for
    p in ("normal-reserve-hand.toml", "planning-reserve-hand.toml", "reserve-hand-freeze.toml")
]
any(ispath, paths)&&error("解析配置已经冻结；不覆盖")
d=TOML.parsefile(joinpath(root, "configs/r7/normal-hand.toml"))
d["name"]="synthetic_r7_anticipatory_battery_hand_v1"
d["heat"]["load_MW"][2]=fill(0.4, 4)
S=342.15;
R=S-0.4/(4200/1e6*5)
d["heat"]["S_reference_K"]=S;
d["heat"]["R_reference_K"]=R
p=only(d["heat"]["pipes"])
for (side, temp) in (("S", S), ("R", R))
    p["history_$(side)_K"]=[[temp, temp]]
    p["initial_$(side)_profiles"]=[Dict("mass_kg"=>[18000.0], "temperature_K"=>[temp]) for _ in 1:2]
end
chp=d["devices"][1];
chp["P_min_MW"]=0.0;
chp["previous_P_MW"]=[0.4, 0.4]
b=d["devices"][2];
b["P_max_MW"]=1.0;
b["E_max_MWh"]=1.0
spec=Dict(
    "schema"=>"r7-planning-spec-v1",
    "normal_domain"=>"prescribed_positive_fixed_electric_topology",
    "recovery_model"=>"r7_recovery_checked_v1",
    "events"=>[
        Dict(
            "id"=>"hour$t",
            "event_start"=>t,
            "periods"=>1,
            "renewable_factor"=>0.5,
            "loss_limit_MWh"=>0.0,
        ) for t in (2, 3)
    ],
)
for (path, data) in zip(paths[1:2], (d, spec))
    open(io->TOML.print(io, data; sorted = true), path, "w")
end
rule=Dict(
    "schema"=>"r7-reserve-hand-freeze-v1",
    "origin"=>"synthetic",
    "frozen_before_optimization"=>true,
    "normal_cost_USD"=>192.0,
    "robust_cost_USD"=>193.275,
    "expected_battery_energy_at_events_MWh"=>0.8,
    "derivation"=>"无损周期热量1.6MWh固定CHP总电量；电负荷3.2MWh，PCC总购电1.6MWh。费用=20*1.6+100*1.6=192。断线时负荷节点需电池0.8MWh；两事件是互斥可能事件，同一正常计划持有0.8MWh至第3小时。充放总吞吐加权至少2*(0.25*(0.8-0.2)+0.75*(0.8-0.15))=1.275，故安全费用下界193.275。还须数值验证热库存及网络共同可行以达到下界。",
    "files"=>Dict(
        replace(relpath(p, root), '\\'=>'/')=>bytes2hex(sha256(read(p))) for p in paths[1:2]
    ),
)
open(io->TOML.print(io, rule; sorted = true), paths[3], "w")
println("Frozen analytical input; no optimization executed.")
