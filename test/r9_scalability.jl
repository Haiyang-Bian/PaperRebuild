using JuMP, Clarabel, SHA, TOML
isdefined(@__MODULE__, :r9_trading_fixture) || include("fixtures/r9_trading.jl")

function r9sc_fixture()
    d=deepcopy(r9_trading_fixture(; T = 2, store = true).data)
    for a in d["actors"][2:end]
        a["flex"]=0.5
        a["sat_P"]=40.0
        a["sat_H"]=20.0
    end
    R9TradingCase(d)
end

function r9sc_record(c, values)
    cost=PaperRebuild.r9_trading_costs(c, values)
    objective=sum(cost.resource)+cost.external+c.data["dt_h"]*sum(
        sum(sum, values[key]) for key in ("w_P", "w_H")
    )
    Dict{String,Any}(
        "input_sha256"=>c.sha256,
        "stage"=>"central",
        "actor"=>0,
        "electric"=>"socp",
        "operation"=>"central",
        "values"=>values,
        "solver_objective"=>objective,
    )
end

function r9sc_solve(c)
    modes=Dict(
        "z_storage"=>zeros(Int, length(c.data["devices"]), c.data["T"]),
        "heat_direction"=>ones(Int, length(c.data["heat"]["pipes"]), c.data["T"]),
    )
    optimizer=optimizer_with_attributes(
        Clarabel.Optimizer,
        "tol_feas"=>1e-10,
        "tol_gap_abs"=>1e-10,
        "tol_gap_rel"=>1e-10,
    )
    b=build_r9_trading_model(c; modes, optimizer)
    set_silent(b.model)
    set_time_limit_sec(b.model, 60.0)
    optimize!(b.model)
    @test termination_status(b.model)==MOI.OPTIMAL
    values=Dict(k=>PaperRebuild.r2_extract(v) for (k, v) in b.variables)
    r=r9sc_record(c, values)
    @test abs(r["solver_objective"]-objective_value(b.model))<=1e-6
    @test validate_r9_trading_solution(c, r)["model_pass"]
    @test abs(objective_value(b.model)-dual_objective_value(b.model))/max(
        1,
        abs(objective_value(b.model)),
    )<=1e-4
    r
end

@testset "R9-SC1 input invariants and tamper rejection" begin
    parent=r9sc_fixture()
    original=deepcopy(parent.data)
    for k in (1, 2, 4)
        child, mapping=r9_split_aggregators(parent, k)
        audit=audit_r9_aggregator_split(parent, child, mapping)
        @test audit["input_rule_pass"] && !audit["physical_feasibility_certified"]
        @test audit["child_aggregators"]==2k
        @test length(child.data["devices"])==length(parent.data["devices"])
        @test child.data["electric"]==parent.data["electric"]
        @test child.data["heat"]==parent.data["heat"]
        @test PaperRebuild.r9_distributed_cost_scale(child)≈PaperRebuild.r9_distributed_cost_scale(
            parent,
        )
        @test TOML.parse(PaperRebuild.r4_text(mapping))==mapping
        @test parent.data==original
        if k==1
            @test child.source_text==parent.source_text && child.sha256==parent.sha256
        else
            # 篡改者即使重新签输入哈希，也不能绕过参数与归属核对。
            for change in (
                d->(d["actors"][2]["sat_P"]+=1),
                d->(d["actors"][2]["electric_node"]=1),
                d->(d["devices"][end]["energy_max_MWh"]+=1),
                d->(d["grid_price"][1]+=1),
            )
                d=deepcopy(child.data)
                change(d)
                text=PaperRebuild.r4_text(d)
                bad=R9TradingCase(TOML.parse(text), bytes2hex(sha256(text)), text)
                receipt=deepcopy(mapping)
                receipt["child_sha256"]=bad.sha256
                @test_throws ErrorException audit_r9_aggregator_split(parent, bad, receipt)
            end
        end
        badmap=deepcopy(mapping)
        badmap["copy_index"][2]=2
        @test_throws ErrorException audit_r9_aggregator_split(parent, child, badmap)
        badmap=deepcopy(mapping)
        badmap["parent_sha256"]=repeat("0", 64)
        @test_throws ErrorException audit_r9_aggregator_split(parent, child, badmap)
        badmap=deepcopy(mapping)
        badmap["parent_for_actor"]=Float64.(badmap["parent_for_actor"])
        @test_throws ErrorException audit_r9_aggregator_split(parent, child, badmap)
    end
    for k in (0, -1, 3, 1.0, true)
        @test_throws ErrorException r9_split_aggregators(parent, k)
    end
    bad=r9sc_fixture()
    bad.data["actors"][2]["P_load"][1]+=0.1
    @test_throws ErrorException r9_split_aggregators(bad, 2)
    forged=R9TradingCase(parent.data, repeat("0", 64), parent.source_text)
    @test_throws ErrorException r9_split_aggregators(forged, 2)
end

@testset "R9-SC2 centralized lift, collapse and unchanged binary domain" begin
    parent=r9sc_fixture()
    original=r9sc_solve(parent)
    for k in (1, 2, 4)
        child, mapping=r9_split_aggregators(parent, k)
        lifted=r9_split_values(parent, child, mapping, original["values"])
        r=r9sc_record(child, lifted)
        @test validate_r9_trading_solution(child, r)["model_pass"]
        @test r["solver_objective"]≈original["solver_objective"]
        @test r9_split_values(parent, child, mapping, lifted; direction = :aggregate)==original["values"]
        @test lifted["m_source"]==original["values"]["m_source"]
        @test lifted["z_storage"]==original["values"]["z_storage"]
        solved=r9sc_solve(child)
        @test abs(solved["solver_objective"]-original["solver_objective"])/max(
            1,
            abs(original["solver_objective"]),
        )<=1e-4
        collapsed=r9_split_values(parent, child, mapping, solved["values"]; direction = :aggregate)
        @test validate_r9_trading_solution(parent, r9sc_record(parent, collapsed))["model_pass"]
        msg=r9_trading_boundary(child, lifted)
        base=r9_trading_boundary(parent, original["values"])
        for i in 2:length(parent.data["actors"]), channel in 1:4
            children=findall(==(i), mapping["parent_for_actor"])
            @test vec(sum(msg[[4(j-2)+channel for j in children], :]; dims = 1))≈base[4(i-2)+channel, :]
        end
        # 新问题仍含原储能/管道整数决策，绝未通过拆分获得额外独立储能模式。
        b=build_r9_trading_model(child)
        p=build_r9_trading_model(parent)
        @test count(is_binary, all_variables(b.model))==count(is_binary, all_variables(p.model))
        bad=deepcopy(lifted)
        bad["P_D"][2][1]=NaN
        @test_throws ErrorException r9_split_values(
            parent,
            child,
            mapping,
            bad;
            direction = :aggregate,
        )
        bad=deepcopy(original["values"])
        bad["boundary"]=[]
        @test_throws ErrorException r9_split_values(parent, child, mapping, bad)
    end
end

@testset "R9-SC3 Jensen gap is not an invariant individual payoff" begin
    parent=r9sc_fixture()
    result=r9sc_solve(parent)
    child, mapping=r9_split_aggregators(parent, 2)
    values=r9_split_values(parent, child, mapping, result["values"])
    x=r9_split_cost_identity(parent, child, mapping, values)
    @test abs(x["identity_error_CNY"])<=1e-10
    @test x["variance_gap_CNY"]==0
    # 仅代数反例：同父的两个子负荷分别偏移±0.125MW，聚合负荷不变。
    values["P_D"][2][1]+=0.125
    values["P_D"][3][1]-=0.125
    x=r9_split_cost_identity(parent, child, mapping, values)
    @test x["variance_gap_CNY"]≈2.5
    @test abs(x["identity_error_CNY"])<=1e-10
    @test abs(x["epigraph_sum_difference_CNY"])<=1e-10
    @test x["child_cost_CNY"]>x["parent_cost_CNY"]
end
