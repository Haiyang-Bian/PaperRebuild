using PaperRebuild, TOML, SHA
root=normpath(joinpath(@__DIR__, ".."))
dest=joinpath(root, "configs/r7/thermal-freeze.toml")
ispath(dest)&&error("不覆盖已冻结热重构协议")
data=TOML.parsefile(joinpath(root, "configs/r7/recovery-hand.toml"))
data["name"]="synthetic_r7_thermal_steady";
data["preplan_id"]="synthetic-declared-steady-profile"
data["electric"]["load_MW"]=[[0.0], [0.4]]
chp=data["devices"][1];
chp["P_min_MW"]=0.4;
chp["P_max_MW"]=0.4;
chp["previous_P_MW"]=[0.4]
data["devices"][2]["initial_MWh"]=[0.0];
data["devices"][2]["E_max_MWh"]=0.0
flow=0.4/(4200/1e6*30)
p=data["heat"]["pipes"][1];
p["normal_flow_kg_s"]=[flow];
p["flow_change_max_kg_s"]=0.0
data["heat"]["reference_flow_kg_s"]=[flow]
records=Dict{String,Any}()
for name in ("thermal-steady", "thermal-front")
    d=deepcopy(data)
    if name=="thermal-front"
        d["name"]="synthetic_r7_same_inventory_different_front"
        d["dt_h"]=0.25
        d["heat"]["load_MW"]=[[0.0], [8/15]]
    end
    c=R7RecoveryCase(d)
    file=joinpath(root, "configs/r7/"*name*".toml")
    ispath(file)&&error("不覆盖已有案例")
    write(file, PaperRebuild.r7_text(c.data))
    records[name]=Dict("case_sha256"=>c.sha256, "file_sha256"=>bytes2hex(sha256(read(file))))
end
rule=Dict(
    "schema"=>"r7-thermal-study-v1",
    "origin"=>"synthetic",
    "cases"=>records,
    "substeps"=>[1, 4, 16],
    "modes"=>["same_dispatch", "curtail_heat"],
    "budget_sec"=>600.0,
    "initial_S_profiles_K"=>Dict("hot_outlet"=>[333.15, 353.15], "cold_outlet"=>[353.15, 333.15]),
    "profile_masses_kg"=>[5000.0, 5000.0],
    "R_initial_K"=>313.15,
    "analytic"=>Dict(
        "steady_unserved_MWh"=>0.0,
        "hot_outlet_unserved_MWh"=>0.0,
        "cold_outlet_same_dispatch"=>"infeasible",
        "cold_outlet_curtail_unserved_MWh"=>1/30,
        "basis"=>"0.25 h moves 20000/7 kg less than half pipe; cold outlet 333.15 K and return minimum 303.15 K limit delivery to 0.4 MW instead of 8/15 MW",
    ),
)
write(dest, PaperRebuild.r7_text(rule))
println("Thermal cases frozen before optimization; no old inputs changed.")
