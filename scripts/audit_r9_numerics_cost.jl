# 保存值的费用、能量和求解器比较；不求解，不把跨模型差称为最优间隙。
using TOML, CSV, Test
include("r9_numerics_study.jl")
length(ARGS)==2 || error("usage: audit_r9_numerics_cost.jl BATCH NEW_OUTPUT")
batch, out=abspath.(ARGS)
ispath(out) && error("不覆盖费用审计")
f=R9NumericsStudy.frozen(batch)
d=f.c.data
rows=NamedTuple[]
hashes=Dict{String,String}()
@testset "R9 cost decomposition and unchanged PV input" begin
    for e in f.manifest["entries"]
        p=joinpath(batch, "runs", e["id"], "result.toml")
        hashes[e["id"]]=R9NumericsStudy.hashfile(p)
        r=TOML.parsefile(p)
        x=r["stage"]["values"]
        dt=d["dt_h"]
        grid=dt*sum(d["grid_price"] .* x["P_grid"])
        chp=dt*sum(
            g["cost_per_MWh"]*sum(x["P_device"][i]) for
            (i, g) in enumerate(d["devices"]) if g["kind"]=="CHP"
        )
        pv=dt*sum(
            g["cost_per_MWh"]*sum(x["P_device"][i]) for
            (i, g) in enumerate(d["devices"]) if g["kind"]=="PV"
        )
        used=dt*sum(sum(x["P_device"][i]) for (i, g) in enumerate(d["devices"]) if g["kind"]=="PV")
        available=dt*sum(sum(g["availability"]) for g in d["devices"] if g["kind"]=="PV")
        cost=r["stage"]["operating_cost"]
        @test abs(grid+chp+pv-cost)<=1e-6max(1, abs(cost))
        @test abs(available-83.16)<=1e-10
        @test abs(used-available)<=1e-6max(1, available)
        energy=Base.invokelatest(() -> getfield(f.mod, :r9_daily_heat_balance)(f.c, x))
        @test energy.pass
        push!(
            rows,
            (
                run_id = e["id"],
                mode = e["mode"],
                solver = e["solver"],
                physical_model = e["physical"],
                cost_CNY = cost,
                grid_CNY = grid,
                chp_CNY = chp,
                pv_CNY = pv,
                pv_available_MWh = available,
                pv_used_MWh = used,
                source_MWh = energy.source_MWh,
                load_MWh = energy.load_MWh,
                pipe_net_MWh = energy.pipe_net_MWh,
                energy_residual_MWh = energy.residual_MWh,
            ),
        )
    end
end
comparisons=NamedTuple[]
for mode in ("CF_CT", "CF_VT")
    a=only(r for r in rows if r.mode==mode && r.solver=="Clarabel")
    for b in (r for r in rows if r.mode==mode && r.solver=="Gurobi")
        push!(
            comparisons,
            (
                first = a.run_id,
                second = b.run_id,
                same_model = !b.physical_model,
                difference_CNY = b.cost_CNY-a.cost_CNY,
                relative_difference = abs(b.cost_CNY-a.cost_CNY)/max(
                    1,
                    abs(a.cost_CNY),
                    abs(b.cost_CNY),
                ),
                interpretation = b.physical_model ?
                                 "cross_grid_form_numerical_check_not_optimality_gap" :
                                 "same_SOCP_A2",
            ),
        )
    end
end
mkpath(out)
CSV.write(joinpath(out, "cost-energy.csv"), rows)
CSV.write(joinpath(out, "comparisons.csv"), comparisons)
cp(@__FILE__, joinpath(out, "audit-source.jl"))
write(
    joinpath(out, "manifest.toml"),
    R9NumericsStudy.textfile(
        Dict(
            "schema"=>"r9-numerics-cost-v1",
            "origin"=>"synthetic",
            "input_sha256"=>f.c.sha256,
            "parent_manifest_sha256"=>R9NumericsStudy.hashfile(joinpath(batch, "manifest.toml")),
            "run_hashes"=>hashes,
            "factors_not_separated"=>"source allocation, time shifting, thermal loss",
            "files"=>Dict(p=>R9NumericsStudy.hashfile(joinpath(out, p)) for p in readdir(out)),
        ),
    ),
)
