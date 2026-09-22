using JuMP, Clarabel, TOML
isdefined(@__MODULE__, :r9_trading_fixture) || include("fixtures/r9_trading.jl")

function r9d_eight_fixture()
    d=deepcopy(r9_trading_fixture(; store = true).data)
    old=deepcopy(d["actors"])
    d["actors"]=[old[1]]
    for i in 1:8
        a=deepcopy(old[i<=4 ? 2 : 3])
        a["id"]="A"*string(i)
        for key in ("P_load", "P_preferred", "H_load", "H_preferred")
            a[key]./=4
        end
        push!(d["actors"], a)
    end
    R9TradingCase(d)
end

function r9d_modes(c)
    Dict(
        "z_storage"=>ones(Int, length(c.data["devices"]), c.data["T"]),
        "heat_direction"=>ones(Int, length(c.data["heat"]["pipes"]), c.data["T"]),
    )
end

function r9d_optimizer()
    optimizer_with_attributes(
        Clarabel.Optimizer,
        "tol_feas"=>1e-10,
        "tol_gap_abs"=>1e-10,
        "tol_gap_rel"=>1e-10,
    )
end

@testset "R9-DC4 R9-DC5 zero-start consensus, replay and cost" begin
    @test_throws ErrorException R9DistributedSpec(; rho = 0)
    @test_throws ErrorException R9DistributedSpec(; max_iterations = 0)
    @test_throws ErrorException R9DistributedSpec(; algorithm = :unregistered)
    for c in (r9_trading_fixture(; store = true), r9d_eight_fixture())
        modes=r9d_modes(c)
        r=solve_r9_distributed(c; optimizer = r9d_optimizer(), modes, budget_sec = 60)
        @test r["status"]=="consensus_converged"
        @test r["validation"]["record_pass"] && r["validation"]["consensus_A4_pass"]
        @test r["validation"]["best_model_found"] && !r["cost_optimization_complete"]
        @test !r["central_solution_injected"] && !r["budget_overrun"]
        @test length(r["trace"])>1
        # 手算：总电负荷2，制热耗电1，PV2，净购电1MWh，成本100CNY。
        @test abs(r["validation"]["best_model_cost_CNY"]-100.0)/100.0<=1e-4
        @test isequal(validate_r9_distributed(c, r), r["validation"])
        for key in ("u", "x", "z")
            bad=deepcopy(r)
            bad["trace"][1][key][1][1]+=0.01
            @test_throws ErrorException validate_r9_distributed(c, bad)
        end
        bad=deepcopy(r)
        bad["trace"][1]["agents"][1]["message"][1][1]+=0.01
        @test_throws ErrorException validate_r9_distributed(c, bad)
        bad=deepcopy(r)
        bad["best_model_iteration"]=0
        @test_throws ErrorException validate_r9_distributed(c, bad)
        bad=deepcopy(r)
        bad["cost_optimization_complete"]=true
        @test_throws ErrorException validate_r9_distributed(c, bad)
    end
end

@testset "R9-DC4 failure states, fixed choices and shared budget" begin
    c=r9_trading_fixture(; store = true)
    modes=r9d_modes(c)
    @test_throws ErrorException solve_r9_distributed(c; optimizer = r9d_optimizer())
    @test_throws ErrorException solve_r9_distributed(
        c;
        optimizer = r9d_optimizer(),
        modes,
        budget_sec = 601,
    )
    bad=deepcopy(modes)
    bad["z_storage"][1]=2
    @test_throws ErrorException solve_r9_distributed(c; optimizer = r9d_optimizer(), modes = bad)
    mip=R9DistributedSpec(; algorithm = :r9_boundary_admm_mip_v1)
    @test_throws ErrorException solve_r9_distributed(
        c;
        optimizer = r9d_optimizer(),
        modes,
        spec = mip,
    )
    short=solve_r9_distributed(
        c;
        optimizer = r9d_optimizer(),
        modes,
        spec = R9DistributedSpec(; max_iterations = 1),
        budget_sec = 60,
    )
    @test short["status"]=="iteration_limit" && length(short["trace"])==1
    @test short["validation"]["record_pass"] && !short["validation"]["consensus_A4_pass"]
    tiny=solve_r9_distributed(c; optimizer = r9d_optimizer(), modes, budget_sec = 1e-8)
    @test tiny["status"]=="time_limit" && isempty(tiny["trace"])
    @test tiny["validation"]["record_pass"] && !tiny["validation"]["best_model_found"]
    license=solve_r9_distributed(
        c;
        optimizer = ()->error("license unavailable"),
        modes,
        budget_sec = 60,
    )
    @test license["status"]=="license_missing" && isempty(license["trace"])
    unsupported=solve_r9_distributed(c; optimizer = r9d_optimizer(), spec = mip, budget_sec = 60)
    @test unsupported["status"]=="unsupported_solver"
    @test unsupported["validation"]["mixed_integer_heuristic"]
    # 源只能供2MW，单个热需求3MW；边界固定且不能通过一致性罚项削减真实负荷。
    d=deepcopy(c.data)
    d["actors"][3]["H_load"]=[3.0]
    d["actors"][3]["H_preferred"]=[3.0]
    impossible=R9TradingCase(d)
    failure=solve_r9_distributed(impossible; optimizer = r9d_optimizer(), modes, budget_sec = 60)
    @test failure["status"]=="infeasible_certified" && isempty(failure["trace"])
    @test !failure["validation"]["best_model_found"]
    @test failure["last_attempt"]["operator"]["termination"]=="INFEASIBLE"
end

@testset "R9-DC5 saved raw controls, frozen replay and tamper rejection" begin
    c=r9_trading_fixture()
    modes=r9d_modes(c)
    r=solve_r9_distributed(c; optimizer = r9d_optimizer(), modes, budget_sec = 60)
    mktempdir() do tmp
        path=save_r9_distributed_run(c, r; directory = tmp, run_id = "analytical")
        readback=read_r9_distributed_run(path; frozen = false)
        @test isequal(readback.validation, r["validation"])
        @test readback.case.sha256==c.sha256
        # 独立目录与冻结库重放，不重新优化，也不依赖原路径。
        moved=joinpath(tmp, "moved")
        cp(path, moved)
        frozen=read_r9_distributed_run(moved)
        @test isequal(frozen.validation, r["validation"])
        @test_throws ErrorException save_r9_distributed_run(
            c,
            r;
            directory = tmp,
            run_id = "analytical",
        )
        @test_throws ErrorException save_r9_distributed_run(
            c,
            r;
            directory = tmp,
            run_id = "../escape",
        )
        open(joinpath(moved, "result.toml"), "a") do io
            write(io, "\n# changed\n")
        end
        @test_throws ErrorException read_r9_distributed_run(moved)
        bad=deepcopy(r)
        bad["source_unchanged"]=false
        @test_throws ErrorException save_r9_distributed_run(
            c,
            bad;
            directory = tmp,
            run_id = "bad-source",
        )
    end
end

@testset "R9-DC2 R9-DC4 fixed topology modes and intertemporal storage" begin
    p=TOML.parsefile(joinpath(@__DIR__, "../configs/r9/network-protocol.toml"))
    for side in ("electric", "heat")
        p[side*"_ties"]=[[1, 3]]
        p[side*"_base_switches"]=[[1, 2], [2, 3]]
    end
    c=r9_reconfiguration_case(r9_trading_fixture(; T = 2, store = true), p; policy = :fixed)
    modes=r9d_modes(c)
    modes["u_E"]=repeat(reshape(c.data["network_control"]["electric_initial"], :, 1), 1, 2)
    modes["u_H"]=reshape(c.data["network_control"]["heat_initial"], :, 1)
    modes["heat_direction"]=repeat(modes["u_H"], 1, 2)
    # 先充后放，维持同一终端能量；单时段全充模式不代替跨时耦合检查。
    modes["z_storage"][end, :]=[1, 0]
    r=solve_r9_distributed(c; optimizer = r9d_optimizer(), modes, budget_sec = 60)
    @test r["status"]=="consensus_converged"
    @test r["validation"]["last_model_pass"] && r["validation"]["record_pass"]
    @test abs(r["validation"]["best_model_cost_CNY"]-200.0)/200.0<=1e-4
    @test all(row->row["operator"]["convex_fixed_mode"], r["trace"])
    missing=deepcopy(modes)
    delete!(missing, "u_H")
    @test_throws ErrorException solve_r9_distributed(
        c;
        optimizer = r9d_optimizer(),
        modes = missing,
    )
    tampered=deepcopy(r)
    tampered["trace"][end]["agents"][1]["values"]["z_storage"][end][1]=0.5
    @test_throws ErrorException validate_r9_distributed(c, tampered)
end

function r9d_solve!(model)
    set_silent(model)
    set_time_limit_sec(model, 60.0)
    set_optimizer_attribute(model, "tol_feas", 1e-10)
    set_optimizer_attribute(model, "tol_gap_abs", 1e-10)
    set_optimizer_attribute(model, "tol_gap_rel", 1e-10)
    optimize!(model)
    @test termination_status(model)==MOI.OPTIMAL
end

function r9d_snapshot(c, b)
    Dict{String,Any}(
        "input_sha256"=>c.sha256,
        "actor"=>b.actor,
        "values"=>Dict(k=>PaperRebuild.r2_extract(x) for (k, x) in b.variables),
        "message"=>PaperRebuild.r2_extract(b.message),
        "cost"=>value(b.cost),
    )
end

@testset "R9-DC1 finite message boxes and separate heat ports" begin
    c=r9_trading_fixture(; T = 2, store = true)
    box=r9_boundary_contract(c)
    @test size(box.lower)==size(box.upper)==(8, 2)
    @test box.lower[1, :]==[-2, -2] && box.upper[1, :]==[2, 2]
    @test box.lower[5, :]==box.upper[5, :]==[-1, -1]
    @test box.lower[8, :]==box.upper[8, :]==[1, 1]
    @test all(box.scale .> 0) && box.scale[2]==1
    @test_throws ErrorException build_r9_distributed_block(c; actor = 0)
    @test_throws ErrorException build_r9_trading_model(c; stage = :operator, actor = 2)
    bad=r9_trading_fixture()
    bad.data["dt_h"]=2.0
    @test_throws ErrorException r9_boundary_contract(bad)
    # 储热的充/放分别进入两个端口；由原允许类型改变电池构造纯数值极限例。
    d=deepcopy(c.data)
    d["devices"][end]["kind"]="HS"
    d["devices"][end]["electric_node"]=0
    d["devices"][end]["heat_node"]=2
    heat=R9TradingCase(d)
    G, A, T=length(d["devices"]), length(d["actors"]), d["T"]
    s=Dict(k=>[zeros(T) for _ in 1:G] for k in ("P_gen", "P_cons", "H_gen", "H_cons"))
    for key in ("P_D", "H_D")
        s[key]=[zeros(T) for _ in 1:A]
    end
    s["H_gen"][end]=[0.7, 0.0]
    s["H_cons"][end]=[0.0, 0.4]
    m=r9_trading_boundary(heat, s; actor = 2)
    @test m[3, :]==[0.7, 0.0] && m[4, :]==[0.0, 0.4]
    @test_throws ErrorException r9_trading_boundary(heat, s; actor = 1)
    s["H_gen"][end][1]=NaN
    @test_throws ErrorException r9_trading_boundary(heat, s)
end

@testset "R9-DC2 R9-DC3 central embedding and consensus assembly" begin
    for c in (r9_trading_fixture(; store = true), r9d_eight_fixture())
        modes=r9d_modes(c)
        central=build_r9_trading_model(c; modes, optimizer = Clarabel.Optimizer)
        r9d_solve!(central.model)
        controls=Dict(k=>PaperRebuild.r2_extract(x) for (k, x) in central.variables)
        message=r9_trading_boundary(c, controls)
        @test maximum(abs, message-value.(central.boundary))<=1e-10
        parts=Any[]
        points=Any[]
        for i in eachindex(c.data["actors"])
            b=build_r9_distributed_block(c; actor = i, modes, optimizer = Clarabel.Optimizer)
            @test b.convex_fixed_mode && !any(is_binary, all_variables(b.model))
            @test iszero(b.base.retail)
            point=Dict(x=>0.0 for x in all_variables(b.model))
            for (key, vars) in b.variables
                if key=="boundary"
                    for I in CartesianIndices(vars)
                        point[vars[I]]=message[I]
                    end
                elseif key in ("P_gen", "P_cons", "H_gen", "H_cons", "E", "z_storage")
                    for I in CartesianIndices(vars)
                        c.data["devices"][I[1]]["owner"]==i &&
                            (point[vars[I]]=controls[key][I[1]][I[2]])
                    end
                elseif key in ("P_D", "H_D", "w_P", "w_H")
                    for t in axes(vars, 2)
                        point[vars[i, t]]=controls[key][i][t]
                    end
                else
                    for I in CartesianIndices(vars)
                        point[vars[I]]=length(Tuple(I))==1 ? controls[key][I[1]] :
                                       controls[key][I[1]][I[2]]
                    end
                end
            end
            # 检查原约束与原变量界，不通过force固定删除边界制造嵌入成功。
            @test isempty(primal_feasibility_report(b.model, point; atol = 1e-7))
            @test maximum(abs, [value(x->point[x], f) for f in b.message]-message[b.rows, :])<=1e-10
            push!(points, value(x->point[x], b.cost))
            for k in axes(b.message, 1), t in axes(b.message, 2)
                @constraint(b.model, b.message[k, t]==message[b.rows[k], t])
            end
            r9d_solve!(b.model)
            push!(parts, r9d_snapshot(c, b))
        end
        @test isapprox(sum(points), objective_value(central.model); atol = 1e-6, rtol = 1e-8)
        candidate=PaperRebuild.r9_distributed_candidate(c, parts[2:end], parts[1])
        @test candidate["validation"]["model_pass"]
        @test candidate["validation"]["heat_energy_mass_pass"]
        @test abs(candidate["operating_cost_CNY"]-objective_value(central.model))/max(
            1,
            abs(objective_value(central.model)),
        )<=1e-4
        @test !candidate["cost_optimization_complete"]
        @test_throws ErrorException PaperRebuild.r9_distributed_candidate(
            c,
            parts[2:(end-1)],
            parts[1],
        )
        # 保留原网络变量，故意改变主体控制应暴露物理不一致，不能暗中平衡。
        wrong=deepcopy(parts[2:end])
        wrong[1]["values"]["P_D"][2][1]+=0.1
        broken=PaperRebuild.r9_distributed_candidate(c, wrong, parts[1])
        @test !broken["validation"]["model_pass"]
    end
end
