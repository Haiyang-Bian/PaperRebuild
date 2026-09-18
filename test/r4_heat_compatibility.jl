using Test, PaperRebuild, JuMP, Clarabel, TOML

function heat_handcase()
    c=load_r4_case(joinpath(@__DIR__, "..", "configs", "r4", "reconfiguration", "oracle.toml"))
    cp=c.data["heat"]["cp"]/1e6
    Ls=0.00126
    Lr=0.00054
    S=[353.15, 353.15-Ls/cp, 353.15-2Ls/cp]
    R=[313.15-2Lr/cp, 313.15-Lr/cp, 313.15]
    q=Dict{String,Any}(
        "H_src"=>[[cp*(S[1]-R[1])], [0.0], [0.0]],
        "H_D"=>[[0.0], [0.0], [cp*(S[3]-R[3])]],
        "H_in"=>[[cp*(S[1]-R[1])], [cp*(S[2]-R[2])], [0.0], [0.0], [0.0], [0.0]],
        "H_out"=>[[cp*(S[2]-R[2])], [cp*(S[3]-R[3])], [0.0], [0.0], [0.0], [0.0]],
        "m_pipe"=>[[1.0], [1.0], [0.0], [0.0], [0.0], [0.0]],
        "m_source"=>[[1.0], [0.0], [0.0]],
        "m_load"=>[[0.0], [0.0], [1.0]],
        "u_H_arc"=>[[1.0], [1.0], [0.0], [0.0], [0.0], [0.0]],
    )
    p=Dict{String,Any}("input_sha256"=>c.sha256, "values"=>q, "operating_cost"=>7.0)
    vals=Dict{String,Any}(k=>deepcopy(q[k]) for k in ("m_pipe", "m_source", "m_load"))
    for (key, x) in (
        ("τ_S", S),
        ("τ_R", R),
        ("τ_source", S),
        ("τ_load", R),
        ("τ_S_out", [S[2], S[3], 353.15, 353.15, 353.15, 353.15]),
        ("τ_R_out", [R[1], R[2], 313.15, 313.15, 313.15, 313.15]),
    )
        vals[key]=[[v] for v in x]
    end
    r=Dict{String,Any}(
        "input_sha256"=>c.sha256,
        "parent_sha256"=>PaperRebuild.r4_heat_parent_hash(p),
        "spec"=>PaperRebuild.r4_heat_spec(R4HeatCompatibilitySpec()),
        "values"=>vals,
    )
    c, p, r
end

@testset "R4-HC1 R4-HC2 R4-HC3 R4-HC4 R4-HC5 heat compatibility" begin
    c, p, r=heat_handcase()
    @test validate_r4_heat_reconstruction(c, p, r)["pass"]
    @test r["values"]["τ_S"][1][1]>r["values"]["τ_S"][3][1]
    @test r["values"]["τ_R"][3][1]>r["values"]["τ_R"][1][1]
    bad=deepcopy(r)
    bad["values"]["m_pipe"][2][1]=0
    @test !validate_r4_heat_reconstruction(c, p, bad)["pass"]
    bad=deepcopy(r)
    bad["values"]["τ_S_out"][1][1]+=0.1
    @test !validate_r4_heat_reconstruction(c, p, bad)["pass"]
    bad=deepcopy(r)
    bad["values"]["τ_source"][1][1]=380
    @test !validate_r4_heat_reconstruction(c, p, bad)["pass"]
    bad=deepcopy(r)
    bad["values"]["m_pipe"][3][1]=1
    @test !validate_r4_heat_reconstruction(c, p, bad)["pass"]
    bad=deepcopy(r)
    bad["values"]["τ_R"][1][1]=NaN
    @test_throws ErrorException validate_r4_heat_reconstruction(c, p, bad)
    pp=deepcopy(p)
    pp["operating_cost"]=8
    @test_throws ErrorException validate_r4_heat_reconstruction(c, pp, r)
    @test_throws ErrorException R4HeatCompatibilitySpec(supply_K = (360, 350))
    @test_throws ErrorException R4HeatCompatibilitySpec(return_K = (NaN, 320))
    @test_throws ErrorException R4HeatCompatibilitySpec(level = :physical_full)
    opt=optimizer_with_attributes(Clarabel.Optimizer, "tol_feas"=>1e-10, "tol_gap_abs"=>1e-10)
    env=R4HeatCompatibilitySpec(level = :envelope)
    b=build_r4_heat_reconstruction(c, p; spec = env)
    @test all(
        F!=JuMP.GenericQuadExpr{Float64,VariableRef} for (F, _) in list_of_constraint_types(b.model)
    )
    solved=reconstruct_r4_heat(c, p; spec = env, optimizer = opt)
    @test solved["validation"]["pass"]
    @test solved["operating_cost"]==7
    @test !solved["validation"]["temperature_checked"]
    wrong=deepcopy(p)
    wrong["values"]["m_pipe"][2][1]=0
    fixed=reconstruct_r4_heat(
        c,
        wrong;
        spec = R4HeatCompatibilitySpec(level = :envelope, fixed_mass = true),
        optimizer = opt,
    )
    @test fixed["status"]=="solver_infeasible"
    free=reconstruct_r4_heat(c, wrong; spec = env, optimizer = opt)
    @test free["validation"]["pass"]
    @test free["values"]["m_pipe"][2][1]>0.1
    limited=deepcopy(c.data)
    limited["heat"]["pipes"][2]["flow_max"]=0.001
    limited["heat"]["pipes"][5]["flow_max"]=0.001
    cc=R4Case(limited)
    pp=deepcopy(p)
    pp["input_sha256"]=cc.sha256
    no=reconstruct_r4_heat(cc, pp; spec = env, optimizer = opt)
    @test no["status"]=="solver_infeasible"
    @test_throws ErrorException reconstruct_r4_heat(
        c,
        p;
        spec = env,
        optimizer = opt,
        budget_sec = 0,
    )
    timed=reconstruct_r4_heat(c, p; spec = env, optimizer = opt, deadline = time()-1)
    @test timed["status"]=="budget_exhausted_before_solve"
    unsupported=reconstruct_r4_heat(c, p; optimizer = opt)
    @test unsupported["status"]=="solver_or_build_error"
    mktempdir() do path
        target=joinpath(path, "saved")
        save_r4_heat_run(target, c, p, solved)
        @test read_r4_heat_run(target).validation["pass"]
        @test_throws ErrorException save_r4_heat_run(target, c, p, solved)
        open(joinpath(target, "parent.toml"), "a") do io
            write(io, "\n# tampered\n")
        end
        @test_throws ErrorException read_r4_heat_run(target)
    end
end
