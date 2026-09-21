using PaperRebuild, TOML, Test

let
    pr=PaperRebuild
    root=dirname(@__DIR__)
    source=joinpath(root, "docs/reading/ch07")
    protocol=joinpath(root, "configs/r9/resilience-protocol.toml")
    @testset "R9-RW2 common clock, source assets and frozen resilience inputs" begin
        a=r9_resilience_template(source, protocol)
        b=r9_resilience_template(source, protocol; critical_set = "nodes_figure_7_14")
        @test a.normal.data["periods"]==96
        @test a.normal.data["dt_h"]==0.25
        @test a.normal.data["currency"]=="CNY"
        @test a.evidence["total_peak_MW"]≈41.103 atol=1e-10
        @test a.evidence["critical_peak_MW"]≈13.75 atol=1e-10
        @test a.evidence["fault_universe_count"]==42
        @test length(a.normal.data["electric"]["lines"])==47
        @test sum(pr.r7_switch_control_mask(a.normal.data))==11
        @test count(l->l["vulnerable"], a.normal.data["electric"]["lines"])==6
        @test count(g->g["kind"]=="BES", a.normal.data["devices"])==0
        @test a.normal.data["electric"]==b.normal.data["electric"]
        @test a.normal.data["heat"]==b.normal.data["heat"]
        @test a.normal.data["devices"]==b.normal.data["devices"]
        @test a.normal.data["load_service"]!=b.normal.data["load_service"]
        @test only(a.planning.specification["events"])["event_start"]==41
        @test only(a.planning.specification["events"])["periods"]==16
        @test a.evidence["steady_source_heat_MW"][1]≈5.555645061761839 atol=1e-10
        @test a.evidence["steady_source_heat_MW"][15]≈0.6542025790048294 atol=1e-10
        @test a.evidence["steady_heat_loss_MW"]≈0.4258476407666742 atol=1e-10
        ds=Dict(g["id"]=>g for g in a.normal.data["devices"])
        @test ds["PV1"]["P_max_MW"]==2
        @test ds["GT1"]["cost_P_MWh"]==771.3
        @test ds["CHP1"]["P_max_MW"]==8.5
        @test ds["CHP2"]["P_max_MW"]==6
        @test ds["CHP2"]["previous_P_MW"][1]≈4.629704218134866 atol=1e-10
        @test pr.r7_chp_steps(ds["CHP2"]["min_on_h"], 0.25)==8
        @test ds["CHP2"]["ramp_MW_h"]*0.25==1.5
        h=a.normal.data["heat"]
        for pipe in h["pipes"], side in ("S", "R")
            state=pr.r7_normal_initial(a.normal.data, pipe, side, 1)
            inlet=only(state.segments).base_K+only(state.segments).amplitude_K
            f=first(pipe["normal_flow_kg_s"])
            before=r7_pipe_inventory(state; cp_J_kgK = h["c_J_kgK"], reference_K = h[side*"_min_K"])
            step=r7_pipe_step(
                state;
                mass_flow_kg_s = f,
                inlet_K = inlet,
                ambient_K = h["ambient_K"][1],
                dt_h = 0.25,
                cp_J_kgK = h["c_J_kgK"],
                UA_W_K = pipe["UA_$(side)_W_K"],
                reference_K = h[side*"_min_K"],
            )
            after=r7_pipe_inventory(
                step.state;
                cp_J_kgK = h["c_J_kgK"],
                reference_K = h[side*"_min_K"],
            )
            @test after.relative_heat_MWh≈before.relative_heat_MWh atol=1e-10
            @test step.outlet_mean_K≈h["ambient_K"][1]+(inlet-h["ambient_K"][1])*exp(
                -pipe["UA_$(side)_W_K"]/(h["c_J_kgK"]*f),
            ) atol=1e-10
        end
        @test_throws ErrorException r9_resilience_template(
            source,
            protocol;
            critical_set = "merged",
        )
        e=pr.r7_event_template(a.planning, 1)
        @test sum(a.evidence["pilot_faults"]["author_event1"])==3
        @test sum(a.evidence["pilot_faults"]["external_only"])==0
        @test e.data["electric"]["switch_control"]==a.normal.data["electric"]["switch_control"]
        @test e.data["load_service"]["critical_load_MW"]==[
            row[41:56] for row in a.normal.data["load_service"]["critical_load_MW"]
        ]
    end
end
