using Test, PaperRebuild, JuMP, HiGHS, Clarabel, TOML, SHA

@testset "R7 inherited-state recovery, not complete disaster planning" begin
    root = normpath(joinpath(@__DIR__, ".."))
    c = load_r7_recovery_case(joinpath(root, "configs/r7/recovery-hand.toml"))
    opt = optimizer_with_attributes(
        HiGHS.Optimizer,
        "threads"=>1,
        "primal_feasibility_tolerance"=>1e-9,
        "dual_feasibility_tolerance"=>1e-9,
        "mip_feasibility_tolerance"=>1e-9,
        "mip_rel_gap"=>1e-9,
    )
    val(r, k) = PaperRebuild.r7_unpack(r["values"], k)
    healthy = solve_r7_recovery(c, [0]; optimizer = opt)
    failed = solve_r7_recovery(c, [1]; optimizer = opt)
    @testset "R7-recovery-hand and R7-fault-certificates" begin
        @test r7_faults(c) == [[0], [1]]
        @test healthy["candidate_accepted"] && healthy["loss_optimization_complete"]
        @test healthy["solver_objective_MWh"] ≈ 0 atol=1e-8
        @test failed["candidate_accepted"] && failed["loss_optimization_complete"]
        @test failed["solver_objective_MWh"] ≈ 17/30 atol=1e-8
        @test failed["validation"]["loss_electric_MWh"] ≈ 0.4
        @test failed["validation"]["loss_heat_MWh"] ≈ 1/6
        @test all(iszero, val(healthy, "P_PCC"))
        @test val(failed, "P")[1, 1, 1] == 0 # CHP保持启停，但能从灾前0.5MW调整至0。
        @test val(failed, "E_BES")[2, 2, 1] ≈ 0 atol=1e-8
        @test !failed["preplan_optimality_verified"]
        @test !failed["validation"]["detailed_heat_validated"]
        @test !failed["validation"]["ac_grid_validated"]
        en = enumerate_r7_recovery(c, [1]; optimizer = opt)
        @test en["gap_certified"] && en["all_topologies_scanned"]
        @test en["upper_bound_MWh"] ≈ 17/30
        cv = enumerate_r7_recovery(c, [1]; optimizer = Clarabel.Optimizer)
        @test cv["upper_bound_MWh"] ≈ 17/30 atol=1e-6
        if haskey(only(cv["runs"]), "bound_unavailable")
            @test !cv["gap_certified"] # 缺ObjectiveBound时不制造数值证书。
        end
        a = audit_r7_faults(c; optimizer = opt)
        @test a["status"] == "violation_certified"
        @test a["all_faults_attempted"] && a["expected_faults"] == 2
        @test a["lower_bound_MWh"] ≈ a["upper_bound_MWh"] ≈ 17/30
        d = deepcopy(c.data)
        d["loss_limit_MWh"] = 0.6
        @test audit_r7_faults(R7RecoveryCase(d); optimizer = opt)["status"] == "safe_adopted_model"
        @test audit_r7_faults(c; optimizer = opt, budget_sec = 0)["status"] == "unresolved"
        @test !enumerate_r7_recovery(c, [1]; optimizer = opt, budget_sec = 0)["gap_certified"]
    end
    @testset "R7-recovery-integration and R7-shared-scenarios" begin
        d = deepcopy(c.data)
        d["dt_h"] = 0.5
        half = solve_r7_recovery(R7RecoveryCase(d), [1]; optimizer = opt)
        @test half["candidate_accepted"]
        @test half["solver_objective_MWh"] ≈ 0.2 atol=1e-8
        d["dt_h"] = 2.0
        two = solve_r7_recovery(R7RecoveryCase(d), [1]; optimizer = opt)
        @test two["candidate_accepted"]
        @test two["solver_objective_MWh"] ≈ 47/30 atol=1e-8
        d = deepcopy(c.data)
        d["probabilities"] = [0.25, 0.75]
        d["devices"][1]["previous_P_MW"] = [0.5, 0.5]
        d["devices"][2]["initial_MWh"] = [0.2, 0.2]
        d["heat"]["pipes"][1]["initial_S_K"] = [343.15, 343.15]
        d["heat"]["pipes"][1]["initial_R_K"] = [313.15, 313.15]
        push!(
            d["devices"],
            Dict(
                "id"=>"PV2",
                "kind"=>"PV",
                "electric_node"=>2,
                "P_max_MW"=>0.4,
                "available_MW"=>[[0.0, 0.4]],
            ),
        )
        shared = R7RecoveryCase(d)
        b = build_r7_recovery(shared, [1])
        @test b.model_class == "MILP"
        @test size(b.variables["z"]) == (1,)
        @test size(b.variables["m_pipe"]) == (1, 1)
        @test size(b.variables["P"]) == (3, 1, 2)
        r = solve_r7_recovery(shared, [1]; optimizer = opt)
        @test r["candidate_accepted"]
        @test r["solver_objective_MWh"] ≈ 5/12 atol=1e-8
        @test val(r, "P")[3, 1, 2] ≈ 0.2 atol=1e-8
        @test build_r7_recovery(shared, [1]; fixed_z = [0]).model_class == "LP"
    end
    @testset "R7-network-direction and R7-hard-failure" begin
        d = deepcopy(c.data)
        d["electric"]["lines"][1]["from"], d["electric"]["lines"][1]["to"] = 2, 1
        forward = solve_r7_recovery(R7RecoveryCase(d), [0]; optimizer = opt, fixed_z = [1])
        @test forward["candidate_accepted"]
        @test forward["solver_objective_MWh"] ≈ 17/30 atol=1e-8
        d["electric"]["flow_domain"] = "signed"
        signed = solve_r7_recovery(R7RecoveryCase(d), [0]; optimizer = opt, fixed_z = [1])
        @test signed["candidate_accepted"]
        @test signed["solver_objective_MWh"] ≈ 0 atol=1e-8
        d = deepcopy(c.data)
        d["electric"]["root_eligible"][2] = 0
        @test solve_r7_recovery(R7RecoveryCase(d), [1]; optimizer = opt)["status"] ==
              "infeasible_certified"
        d = deepcopy(c.data)
        d["electric"]["shed_fraction_max"][2] = 0
        @test solve_r7_recovery(R7RecoveryCase(d), [1]; optimizer = opt)["status"] ==
              "infeasible_certified"
        b = build_r7_recovery(c, [1]; optimizer = opt, fixed_z = [0])
        fix(b.variables["v"][1, 1, 1], 0.95; force = true)
        fix(b.variables["v"][2, 1, 1], 1.05; force = true)
        set_silent(b.model)
        optimize!(b.model)
        @test termination_status(b.model) == MOI.OPTIMAL
        @test objective_value(b.model) ≈ 17/30 atol=1e-8
        d = deepcopy(c.data)
        d["devices"][1]["ramp_MW_h"] = 0
        @test solve_r7_recovery(R7RecoveryCase(d), [1]; optimizer = opt)["status"] ==
              "infeasible_certified"
        @test solve_r7_recovery(c, [1]; optimizer = opt, budget_sec = 0)["status"] ==
              "budget_exhausted"
        @test solve_r7_recovery(c, [1]; optimizer = nothing)["status"] == "solver_or_build_error"
    end
    @testset "R7-proxy-boundaries" begin
        d = deepcopy(c.data)
        d["heat"]["pipes"][1]["initial_S_K"] = [338.15]
        d["heat"]["pipes"][1]["initial_R_K"] = [318.15]
        r = solve_r7_recovery(R7RecoveryCase(d), [1]; optimizer = opt)
        @test r["candidate_accepted"]
        @test !r["validation"]["exchange_exact_pass"]
        d = deepcopy(c.data)
        d["devices"][2]["P_max_MW"] = 0.4
        simultaneous_case = R7RecoveryCase(d)
        r = solve_r7_recovery(simultaneous_case, [1]; optimizer = opt)
        ch, dis = val(r, "P_ch"), val(r, "P_dis")
        ch[2, 1, 1], dis[2, 1, 1] = 0.05, 0.25
        r["values"]["P_ch"], r["values"]["P_dis"] =
            PaperRebuild.r7_pack(ch), PaperRebuild.r7_pack(dis)
        v = validate_r7_recovery(simultaneous_case, r)
        @test v["model_pass"] && !v["mutual_exclusivity_pass"]
        @test v["max_simultaneous_charge_discharge_MW"] ≈ 0.05
    end
    @testset "R7-input-and-original-values" begin
        for change in (
            d->(d["units"]["power"]="kW"),
            d->(d["probabilities"]=[0.2]),
            d->(d["renewable_factor"]=1.2),
            d->(d["heat"]["available"]=false),
            d->(d["devices"][2]["initial_MWh"]=[0.4]),
            d->(d["devices"][2]["id"]=d["devices"][1]["id"]),
            d->delete!(d["devices"][1], "previous_P_MW"),
            d->(d["heat"]["pipes"][1]["initial_S_K"]=[300.0]),
            d->(d["electric"]["load_MW"]=[[0.0]]),
        )
            d=deepcopy(c.data)
            change(d)
            @test_throws Exception R7RecoveryCase(d)
        end
        @test_throws Exception build_r7_recovery(c, [2])
        @test_throws Exception build_r7_recovery(c, [1]; fixed_z = [1])
        d=deepcopy(c.data)
        d["electric"]["lines"]=fill(d["electric"]["lines"][1], 4)
        d["electric"]["fault_budget"]=2
        @test length(r7_faults(R7RecoveryCase(d))) == 11
        bad=deepcopy(failed)
        bad["values"]["E_BES"]["data"][end] += 0.1
        @test !validate_r7_recovery(c, bad)["model_pass"]
        bad=deepcopy(failed)
        bad["values"]["z"]["data"][1]=0.2
        @test !validate_r7_recovery(c, bad)["model_pass"]
        bad=deepcopy(failed)
        bad["lower_bound_MWh"]=2.0
        @test !validate_r7_recovery(c, bad)["optimality_pass"]
        bad=deepcopy(failed)
        bad["fixed_z"]=[1]
        @test !validate_r7_recovery(c, bad)["model_pass"]
        bad=deepcopy(failed)
        bad["status"]="infeasible_certified"
        @test_throws Exception validate_r7_recovery(c, bad)
    end
    @testset "R7-save-replay-tamper" begin
        mkpath(joinpath(root, "tmp"))
        mktempdir(joinpath(root, "tmp")) do dir
            dest=joinpath(dir, "run")
            save_r7_recovery(c, failed, dest)
            @test TOML.parsefile(joinpath(dest, "metadata.toml"))["origin"] == "synthetic"
            @test failed["requested_budget_sec"] == 60
            @test read_r7_recovery(dest).result["solver_objective_MWh"] ≈ 17/30
            @test_throws Exception save_r7_recovery(c, failed, dest)
            rp=joinpath(dest, "result.toml")
            fp=joinpath(dest, "files.toml")
            original=read(rp)
            manifest=read(fp)
            write(rp, vcat(original, UInt8[0x20]))
            @test_throws Exception read_r7_recovery(dest)
            write(rp, original)
            bad=TOML.parse(String(copy(original)))
            bad["validation"]["loss_MWh"]=0.0
            write(rp, PaperRebuild.r7_text(bad))
            f=TOML.parse(String(copy(manifest)))
            f["files"]["result.toml"]=bytes2hex(sha256(read(rp)))
            write(fp, PaperRebuild.r7_text(f))
            @test_throws Exception read_r7_recovery(dest) # 即使重算文件哈希，虚假摘要仍被原值拒绝。
            write(rp, original)
            write(fp, manifest)
            write(joinpath(dest, "unexpected.txt"), "extra")
            @test_throws Exception read_r7_recovery(dest)
            rm(joinpath(dest, "unexpected.txt"))
            @test success(
                `$(Base.julia_cmd()) --startup-file=no --project=$root $(joinpath(dest,"code/replay.jl"))`,
            )
        end
    end
end
