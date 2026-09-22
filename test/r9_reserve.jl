module R9ReserveTests
using PaperRebuild, TOML, Test
const ROOT=normpath(joinpath(@__DIR__, ".."))
const SOURCE=joinpath(ROOT, "docs/reading/ch07")
const PROTOCOL=joinpath(ROOT, "configs/r9/reserve-protocol.toml")

@testset "R9-RS original nameplates and independent steady history" begin
    c=r9_reserve_template(SOURCE, PROTOCOL)
    d=c.data
    check=audit_r9_reserve_input(c)
    @test check["reference_pass"]
    @test !check["whole_day_dispatch_verified"]
    @test length(check["rows"])>=414
    @test (
        check["electric_nodes"],
        check["heat_nodes"],
        check["buildings"],
        check["local_P2H_count"],
    )==(44, 38, 36, 4)
    @test d["schema"]=="r5-dispatch-case-v2" && d["currency"]=="CNY"
    @test d["electric"]["root"]==44
    @test d["T"]==24 && d["dt_h"]==1.0
    @test d["heat"]["terminal_rule"]=="free"
    @test all(b["terminal_rule"]=="initial" for b in d["buildings"])
    @test only(filter(g->g["id"]=="PV1", d["devices"]))["p_max_MW"]==2.0
    @test sum(g["p_max_MW"] for g in d["devices"] if g["kind"]=="PV")==8.0
    @test sum(b["P_DH_max_MW"] for b in d["buildings"])≈0.95
    @test all(b["COP_DH"]==0.8 for b in d["buildings"] if b["P_DH_max_MW"]>0)
    @test check["reference_source_heat_MW"]≈[5.730396463418252, 0.6796512725679915] atol=1e-10
    @test c.sha256==r9_reserve_template(SOURCE, PROTOCOL).sha256
    # 电网实际输入是45.67 MVA乘显式0.9功率因数，不能直接解释成45.67 MW。
    @test maximum(sum(d["electric"]["P_load_MW"]))≈45.67*0.9
    # 两项结算价同时加输配费：τ(P_DA-delivery)=τPCC，不对备用容量再收一次。
    for t in 1:24, (pda, pcc) in ((30.0, 25.0), (20.0, 29.0))
        raw=d["r9_reserve"]["protocol"]["market"]["energy_price_CNY_MWh"][t]
        paid=d["award"]["energy_price"][t]*pda-d["realtime"]["price"][t]*(pda-pcc)
        @test paid-raw*pcc≈125.6*pcc atol=1e-9
    end
    for mutate in (
        x->(x["devices"][end]["p_max_MW"]+=1.0),
        x->(x["buildings"][1]["C_MWh_K"]*=2),
        x->(x["award"]["energy_price"][1]+=1),
        x->(x["heat"]["pipes"][1]["history_R_K"][1]+=0.1),
        x->(x["r9_reserve"]["reference"]["R_K"][1]+=0.1),
    )
        x=deepcopy(d)
        mutate(x)
        @test !audit_r9_reserve_input(R5DispatchCase(x))["reference_pass"]
    end
    x=deepcopy(d)
    x["r9_reserve"]["protocol"]["id"]="tampered"
    @test_throws ErrorException audit_r9_reserve_input(R5DispatchCase(x))
    x=deepcopy(d)
    x["heat"]["pipes"][1]["history_S_K"]=Float64[]
    @test_throws ErrorException R5DispatchCase(x)
end

@testset "R9-RS declared capacity and temperature boundary rejection" begin
    p=TOML.parsefile(PROTOCOL)
    for mutate in (
        x->(x["p2h_capacity_basis"]="heat_output"),
        x->(x["electric"]["root"]=1),
        x->(x["heat"]["cp_J_kgK"]=0.0),
        x->(x["heat"]["source15_reference_MW"]=20.0),
        x->(x["heat"]["S_bounds_K"]=[363.15, 373.15]),
    )
        q=deepcopy(p)
        mutate(q)
        mktempdir() do dir
            file=joinpath(dir, "protocol.toml")
            open(io->TOML.print(io, q; sorted = true), file, "w")
            @test_throws ErrorException r9_reserve_template(SOURCE, file)
        end
    end
end
end
