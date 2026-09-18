using Test, PaperRebuild, JuMP, Clarabel, TOML
@testset "R4 network reconfiguration" begin
    root=normpath(joinpath(@__DIR__, ".."))
    c=load_r4_case(joinpath(root, "configs", "r4", "reconfiguration", "oracle.toml"))
    opt=optimizer_with_attributes(
        Clarabel.Optimizer,
        "tol_feas"=>1e-9,
        "tol_gap_abs"=>1e-9,
        "tol_gap_rel"=>1e-9,
    )
    es=c.data["electric"]["edges"]
    @test length(r4_network_states(c, :electric))==3
    @test length(r4_network_states(c, :heat))==3
    @test r4_is_tree(es, [1, 0, 1])
    @test !r4_is_tree(es, [1, 1, 1])
    @test !r4_is_tree(es, [0, 0, 0])
    @test !r4_is_tree(es, [0.5, 1, 0])
    # 非根三节点构成一个环：边数虽为N-1，根仍孤立，必须拒绝。
    cycle=[Dict("from"=>2, "to"=>3), Dict("from"=>3, "to"=>4), Dict("from"=>2, "to"=>4)]
    @test !r4_is_tree(cycle, [1, 1, 1]; nodes = 4)
    @test_throws ErrorException build_r4_model(c)
    bad=deepcopy(c.data)
    bad["network_control"]["stable_history_steps"]=0
    @test_throws ErrorException R4Case(bad)
    bad=deepcopy(c.data)
    bad["heat"]["pipes"][6]["length_m"]+=1
    @test_throws ErrorException R4Case(bad)
    spec=R4ReconfigurationSpec(policy = :fixed)
    opts=(;
        optimizer = opt,
        spec,
        modes = [0],
        electric_schedule = reshape([1, 1, 0], 3, 1),
        heat_open = [1, 1, 0],
        heat_direction = ones(Int, 3, 1),
        budget_sec = 60,
    )
    r=solve_r4_reconfiguration(c; opts...)
    @test r["validation"]["model_pass"]
    @test r["validation"]["electric_original_pass"]
    @test r["switching_cost"]<1e-6
    @test all(
        abs(r["values"][k][3][1])<1e-7 for
        k in ("P_branch", "Q_branch", "ell", "H_in", "H_out", "m_pipe")
    )
    @test all(abs(r["values"]["H_in"][p][1])<1e-7 for p in 4:6)
    @test r["solves"][1]["model_class"]=="SOCP"
    invalid=solve_r4_reconfiguration(c; opts..., electric_schedule = ones(Int, 3, 1))
    @test invalid["status"]=="infeasible_certified"
    @test !invalid["validation"]["model_pass"]
    # 动作成本为每次成本，不乘时间步长。换一条树边涉及开/关两个动作。
    s=deepcopy(r["values"])
    s["u_E"]=[[1.0], [0.0], [1.0]]
    s["u_H"]=[1.0, 0.0, 1.0]
    @test PaperRebuild.r4_switch_cost(c, s)≈0.3
    wrong=deepcopy(r)
    wrong["values"]["u_E"][3][1]=1
    @test !validate_r4_reconfiguration(c, wrong)["model_pass"]
    wrong=deepcopy(r)
    wrong["values"]["H_out"][3][1]=0.01
    @test !validate_r4_reconfiguration(c, wrong)["model_pass"]
    wrong=deepcopy(r)
    wrong["values"]["a_E"][1][1]=1
    @test !validate_r4_reconfiguration(c, wrong)["model_pass"]
    oracle=enumerate_r4_reconfiguration(c; optimizer = opt, budget_sec = 60)
    @test length(oracle["records"])==72
    @test all(haskey(x, "raw") for x in oracle["records"])
    @test oracle["certificate_A2"]
    @test oracle["best_physical_index"]>0
    @test oracle["best_model_cost"]<=r["operating_cost"]+1e-4
    @test validate_r4_network_enumeration(c, oracle)["certificate_A2"]
    missing=deepcopy(oracle)
    pop!(missing["records"])
    @test_throws ErrorException validate_r4_network_enumeration(c, missing)
    duplicated=deepcopy(oracle)
    duplicated["records"][2]=deepcopy(duplicated["records"][1])
    @test_throws ErrorException validate_r4_network_enumeration(c, duplicated)
    full=load_r4_case(joinpath(root, "configs", "r4", "reconfiguration", "import.toml"))
    @test_throws ErrorException enumerate_r4_reconfiguration(full; optimizer = opt)
    # 第2/3时段连续切换违反预先声明的两步动作间隔。
    schedule=[1 1 1 1; 1 0 1 1; 0 1 0 0]
    dwell=solve_r4_reconfiguration(
        full;
        optimizer = opt,
        modes = zeros(Int, 4),
        electric_schedule = schedule,
        heat_open = [1, 1, 0],
        heat_direction = ones(Int, 3, 4),
        budget_sec = 60,
    )
    @test dwell["status"]=="infeasible_certified"
    @test !dwell["validation"]["model_pass"]
    mktempdir() do dir
        path=save_r4_run(c, r; directory = dir, run_id = "network")
        @test isequal(read_r4_run(path).validation, r["validation"])
        open(joinpath(path, "result.toml"), "a") do io
            write(io, "\n# changed\n")
        end
        @test_throws ErrorException read_r4_run(path)
        path2=save_r4_run(c, oracle; directory = dir, run_id = "enumeration")
        @test read_r4_network_enumeration(path2).validation["certificate_A2"]
    end
end
