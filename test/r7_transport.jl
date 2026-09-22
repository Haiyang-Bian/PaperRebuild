using Test, PaperRebuild, JuMP, HiGHS, Clarabel, TOML, SHA

function transport_test_parent(group = "hand")
    dir=joinpath(
        @__DIR__,
        "..",
        "results/summaries/r7-ports-20260920-v1/thermal",
        group*"_fault0_highs",
    )
    manifest=TOML.parsefile(joinpath(dir, "files.toml"))["files"]
    for p in ("case.toml", "parent.toml", "spec.toml")
        @test bytes2hex(sha256(read(joinpath(dir, p))))==manifest[p]
    end
    c=load_r7_recovery_case(joinpath(dir, "case.toml"))
    r=TOML.parsefile(joinpath(dir, "parent.toml"))
    ts=TOML.parsefile(joinpath(dir, "spec.toml"))
    c, r, ts
end

@testset "R7-D detailed heat delivery" begin
    opt=optimizer_with_attributes(
        HiGHS.Optimizer,
        "threads"=>1,
        "primal_feasibility_tolerance"=>1e-9,
        "dual_feasibility_tolerance"=>1e-9,
        "mip_feasibility_tolerance"=>1e-9,
        "mip_rel_gap"=>1e-9,
    )
    c, r, ts=transport_test_parent()
    flow=Dict(k=>PaperRebuild.r7_unpack(r["values"], k) for k in ("m_pipe", "m_source", "m_load"))
    spec=r7_transport_spec(
        c;
        flow_schedule = flow,
        profiles = ts["profiles"],
        profile_origin = "frozen original parent",
        substeps = 16,
    )
    @testset "R7-D2 transport interval conflict" begin
        w=r7_transport_port_witness(c, r, ts)
        @test w["conflict_found"]
        firstload=only(filter(z->z["kind"]=="load"&&z["step"]==1&&z["scenario"]==1, w["rows"]))
        @test firstload["maximum_MW"]≈17/45 atol=1e-12
        @test firstload["gap_MW"]≈1/45 atol=1e-12
        @test !w["sufficiency_claimed"]
        for group in ("reserve_event_1", "reserve_event_2")
            a, b, s=transport_test_parent(group)
            @test r7_transport_port_witness(a, b, s)["conflict_found"]
        end
    end
    @testset "R7-D1 conditional redispatch and original compatibility" begin
        b=build_r7_transport_recovery(c, [0], spec; fixed_z = [1])
        @test b.model_class=="LP"
        @test !haskey(b.constraints, "6-89")
        @test haskey(b.constraints, "R7-T1-transport")
        q=solve_r7_transport_recovery(c, [0], spec; optimizer = opt, budget_sec = 60)
        @test get(q, "error", "")==""
        @test q["validation"]["model_pass"]
        @test q["validation"]["conditional_optimality_pass"]
        @test q["validation"]["loss_MWh"]≈2/45 atol=1e-7
        @test !q["validation"]["shared"]["model_pass"]
        @test q["validation"]["shared"]["shared_block_pass"]
        @test !q["validation"]["full_variable_flow_optimized"]
        qc=solve_r7_transport_recovery(
            c,
            [0],
            spec;
            optimizer = Clarabel.Optimizer,
            fixed_z = [1],
            budget_sec = 60,
        )
        @test qc["validation"]["model_pass"]
        @test qc["validation"]["loss_MWh"]≈q["validation"]["loss_MWh"] atol=1e-6
        # 30K稳态所需流量由原0.4MW手算，设备和输入不变。
        f=0.4/(c.data["heat"]["c_J_kgK"]/1e6*30)
        newflow=Dict(
            "m_pipe"=>fill(f, 1, 1),
            "m_source"=>reshape([f, 0.0], 2, 1),
            "m_load"=>reshape([0.0, f], 2, 1),
        )
        s2=r7_transport_spec(
            c;
            flow_schedule = newflow,
            profiles = ts["profiles"],
            profile_origin = "same frozen initial state",
            substeps = 16,
        )
        fixed=solve_r7_transport_recovery(c, [0], s2; optimizer = opt, budget_sec = 60)
        @test fixed["validation"]["model_pass"]
        @test fixed["validation"]["loss_MWh"]≈0 atol=1e-7
        @testset "R7-D fixed zero ports retain their declared branch" begin
            perturbed=deepcopy(fixed)
            perturbed["values"]["m_load"]["data"][1]=1e-18
            qzero=validate_r7_transport_recovery(c, s2, perturbed)
            @test qzero["model_pass"]
            @test qzero["flow_schedule_residual_kg_s"]==1e-18
            @test perturbed["values"]["m_load"]["data"][1]==1e-18
            @test qzero["thermal_flow_basis"]=="declared_schedule_with_raw_equality_check"
            perturbed["values"]["m_load"]["data"][1]=1e-4
            @test !validate_r7_transport_recovery(c, s2, perturbed)["model_pass"]
        end
        @test validate_r7_recovery(c, r)["model_pass"]
        @test solve_r7_thermal_reconstruction(c, r, ts; optimizer = opt, budget_sec = 60)["status"]=="infeasible_certified"
        @testset "R7-D3 evidence, failures and validation" begin
            mktempdir() do dir
                p=joinpath(dir, "run")
                save_r7_transport_recovery(c, spec, q, p)
                @test read_r7_transport_recovery(p).result["run_id"]==q["run_id"]
                @test_throws ErrorException save_r7_transport_recovery(c, spec, q, p)
                open(joinpath(p, "spec.toml"), "a") do io
                    write(io, "\n# altered")
                end
                @test_throws ErrorException read_r7_transport_recovery(p)
            end
            bad=deepcopy(q)
            bad["thermal_values"]["H_delivered"]["data"][2]+=0.01
            @test !validate_r7_transport_recovery(c, spec, bad)["model_pass"]
            bad=deepcopy(q)
            delete!(bad, "thermal_values")
            @test_throws ErrorException validate_r7_transport_recovery(c, spec, bad)
            @test solve_r7_transport_recovery(c, [0], spec; optimizer = opt, budget_sec = 0)["status"]=="budget_exhausted"
            @test solve_r7_transport_recovery(
                c,
                [0],
                spec;
                optimizer = ()->error("license missing"),
                budget_sec = 60,
            )["status"]=="license_unavailable"
            bad=deepcopy(spec)
            bad["flow_schedule"]["m_source"]["data"][1]+=1
            @test_throws ErrorException build_r7_transport_recovery(c, [0], bad)
            bad=deepcopy(spec)
            bad["flow_schedule"]["m_pipe"]["data"][1]=NaN
            @test_throws ErrorException build_r7_transport_recovery(c, [0], bad)
            bad=deepcopy(spec)
            pop!(bad["profiles"])
            @test_throws ErrorException build_r7_transport_recovery(c, [0], bad)
            bad=deepcopy(spec)
            bad["profiles"][1]["segments"][1]["base_K"]+=0.01
            @test_throws ErrorException build_r7_transport_recovery(c, [0], bad)
            @test solve_r7_transport_recovery(
                c,
                [0],
                spec;
                optimizer = Clarabel.Optimizer,
                budget_sec = 60,
            )["status"]=="solver_or_build_error"
            zero=Dict(k=>zeros(size(v)) for (k, v) in flow)
            sz=r7_transport_spec(
                c;
                flow_schedule = zero,
                profiles = ts["profiles"],
                profile_origin = "same old state",
                substeps = 4,
            )
            rz=solve_r7_transport_recovery(c, [1], sz; optimizer = opt, budget_sec = 60)
            @test rz["validation"]["model_pass"]
            @test rz["validation"]["loss_heat_MWh"]≈0.4 atol=1e-7
            # 断线且固定正源流与正温差，无产热电力消纳端：仍真实不可行。
            @test solve_r7_transport_recovery(c, [1], spec; optimizer = opt, budget_sec = 60)["status"]=="infeasible_certified"
        end
    end
end
