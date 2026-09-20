using TOML, CSV, SHA
include("r9_pv_study.jl")
length(ARGS)==2 || error("usage: r9_pv_attribution.jl BATCH NEW_ATTRIBUTION")
batch,out=abspath.(ARGS)
ispath(out) && error("不覆盖归因")
f=R9PVStudy.frozen(batch)
rows=NamedTuple[]
hashes=Dict{String,String}()
for mode in ("cf_ct","cf_vt")
    id=mode*"_clarabel_socp"
    path=joinpath(batch,"runs",id,"result.toml")
    hashes[id]=R9PVStudy.hashfile(path)
    r=TOML.parsefile(path)
    v=Base.invokelatest(()->getfield(f.mod,:validate_r9_pv_solution)(f.c,r))
    v.physical_pass && v.terminal_pass || error("本归因仅比较原关系/终端通过的同求解器候选")
    d=f.c.data
    x=get(r,"reconstructed",r["stage"])["values"]
    dt=d["dt_h"]
    grid=dt*sum(d["grid_price"].*x["P_grid"])
    chp=dt*sum(g["cost_per_MWh"]*sum(x["P_device"][i]) for (i,g) in enumerate(d["devices"]) if g["kind"]=="CHP")
    pv=dt*sum(g["cost_per_MWh"]*sum(x["P_device"][i]) for (i,g) in enumerate(d["devices"]) if g["kind"]=="PV")
    source=dt*sum(sum(x["H_port"][j]) for j in (1,15))
    load=dt*sum(sum(n["H_MW"]) for n in d["heat"]["nodes"])
    loss=dt*d["heat"]["cp_J_kgK"]/1e6*sum(x["m_pipe"][p][t]*(x["tau_"*side*"_in"][p][t]-x["tau_"*side*"_out"][p][t]) for p in eachindex(d["heat"]["pipes"]), t in 1:d["T"], side in ("S","R"))
    cost=r["stage"]["operating_cost"]
    abs(grid+chp+pv-cost)<=1e-6max(1,abs(cost)) || error("成本分解失败")
    energy_residual=abs(source-load-loss)
    energy_pass=energy_residual<=1e-6max(1,abs(source))
    push!(rows,(id,cost_CNY=cost,grid_CNY=grid,chp_CNY=chp,pv_CNY=pv,source_MWh=source,load_MWh=load,loss_MWh=loss,
        periodic_energy_residual_MWh=energy_residual,periodic_energy_pass=energy_pass))
end
mkpath(out)
CSV.write(joinpath(out,"attribution.csv"),rows)
cp(@__FILE__,joinpath(out,"attribution-source.jl"))
write(joinpath(out,"manifest.toml"),R9PVStudy.textfile(Dict("schema"=>"r9-pv-attribution-v1","parent_manifest_sha256"=>R9PVStudy.hashfile(joinpath(batch,"manifest.toml")),
    "run_hashes"=>hashes,"origin"=>"synthetic","factors_not_separated"=>"source allocation, intertemporal scheduling and temperature-dependent heat loss all change; cost difference is not a pure storage effect",
    "files"=>Dict(p=>R9PVStudy.hashfile(joinpath(out,p)) for p in readdir(out)))))
