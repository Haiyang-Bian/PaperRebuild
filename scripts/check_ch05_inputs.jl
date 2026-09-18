using TOML, Test

"""
核查第5章已转录设备表的索引、单位及容量总计。原文缺失输入不补零，
P2H容量电/热基准未明时不进行转换。本检查不是可运行案例验收。
"""
function check_ch05_inputs()
    d=TOML.parsefile(joinpath(@__DIR__, "..", "docs", "reading", "ch05", "inputs.toml"))
    devices=d["device"]
    @testset "R5 partial thesis tables and unit arithmetic" begin
        @test d["origin"]=="thesis_table_transcription"
        @test d["status"]=="partial_input_not_runnable"
        @test length(devices)==length(unique(x["id"] for x in devices))==11
        @test all(1<=x["electric_node"]<=d["electric_nodes"] for x in devices)
        @test all(!haskey(x, "heat_node") || 1<=x["heat_node"]<=d["heat_nodes"] for x in devices)
        @test all(x["capacity_kW"]>0 for x in devices)
        generation=sum(x["capacity_kW"] for x in devices if x["kind"] in ("PV", "CHP", "GT"))/1000
        pv=sum(x["capacity_kW"] for x in devices if x["kind"]=="PV")/1000
        chp_heat=sum(x["capacity_kW"]*x["heat_to_power"] for x in devices if x["kind"]=="CHP")/1000
        eb_heat=sum(x["capacity_kW"] for x in devices if x["kind"]=="EB")/1000
        @test generation≈d["claimed_total_generation_MW"] atol=1e-12
        @test pv≈d["claimed_PV_capacity_MW"] atol=1e-12
        @test chp_heat+eb_heat≈d["claimed_total_heat_capacity_MW"] atol=1e-12
        @test chp_heat≈2.32 atol=1e-12
        @test eb_heat==1.0
        chp1=only(filter(x->x["id"]=="CHP1", devices))
        @test chp1["capacity_kW"]/1000==2.0
        @test chp1["cost_USD_kWh"]*1000==98.0
        # 满出力一小时的费用在kW/kWh与MW/MWh表示下相同。
        @test chp1["capacity_kW"]*chp1["cost_USD_kWh"]≈2*98 atol=1e-12
        @test all(
            startswith(x["capacity_basis"], "unspecified") for x in devices if x["kind"]=="P2H"
        )
        @test 1-d["chance_confidence"]≈0.05 atol=1e-12
        @test !isempty(d["missing"]) && !isempty(d["ambiguities"])
    end
    println(
        "11 transcribed devices; 5.10MW generation / 3.32MW central heat cross-checked. Inputs remain incomplete.",
    )
end
check_ch05_inputs()
