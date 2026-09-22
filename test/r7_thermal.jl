using Test, PaperRebuild, JuMP, HiGHS, Clarabel, TOML
const R7THERM_ROOT=normpath(joinpath(@__DIR__, ".."))

function thermal_test_parent(name)
    c=load_r7_recovery_case(joinpath(R7THERM_ROOT, "configs/r7/"*name*".toml"))
    r=solve_r7_recovery(
        c,
        [0];
        optimizer = optimizer_with_attributes(HiGHS.Optimizer, "threads"=>1),
        budget_sec = 60,
    )
    c, r
end
function thermal_front_spec(c, r, hot; substeps = 1, mode = :same_dispatch)
    s=r7_thermal_spec(
        c,
        r;
        profiles = :uniform,
        profile_origin = "declared analytic profiles",
        substeps,
        mode,
    )
    p=only(filter(p->p["side"]=="S", s["profiles"]))
    p["segments"]=[
        Dict(
            "mass_kg"=>5000.0,
            "base_K"=>temp,
            "amplitude_K"=>0.0,
            "rate_per_kg"=>0.0,
            "from_left"=>true,
        ) for temp in (hot ? [333.15, 353.15] : [353.15, 333.15])
    ]
    s["uniform_assumption"]=false
    s
end

@testset "R7-T fixed-control thermal reconstruction" begin
    opt=optimizer_with_attributes(HiGHS.Optimizer, "threads"=>1)
    c, r=thermal_test_parent("thermal-steady")
    @test r["validation"]["model_pass"]
    s=r7_thermal_spec(c, r; profiles = :uniform, profile_origin = "explicit steady witness")
    @test build_r7_thermal_reconstruction(c, r, s).model_class=="LP"
    a=solve_r7_thermal_reconstruction(c, r, s; optimizer = opt, budget_sec = 60)
    @test a["validation"]["thermal_model_pass"]
    @test a["validation"]["same_dispatch_pass"]
    @test a["validation"]["conditional_heat_optimality_pass"]
    @test abs(a["validation"]["heat_unserved_MWh"])<=1e-6
    @test !a["validation"]["whole_recovery_certified"]
    a2=solve_r7_thermal_reconstruction(c, r, s; optimizer = Clarabel.Optimizer, budget_sec = 60)
    @test a2["validation"]["thermal_model_pass"]
    @test abs(a2["validation"]["heat_unserved_MWh"]-a["validation"]["heat_unserved_MWh"])<=1e-4
    @test solve_r7_thermal_reconstruction(c, r, s; optimizer = opt, budget_sec = 0)["status"]=="budget_exhausted"
    bad=deepcopy(s)
    pop!(bad["profiles"])
    @test_throws ErrorException build_r7_thermal_reconstruction(c, r, bad)
    bad=deepcopy(s)
    push!(bad["profiles"], deepcopy(first(bad["profiles"])))
    @test_throws ErrorException build_r7_thermal_reconstruction(c, r, bad)
    bad=deepcopy(s)
    bad["profiles"][1]["segments"][1]["base_K"]+=1
    @test_throws ErrorException build_r7_thermal_reconstruction(c, r, bad)
    badr=deepcopy(r)
    badr["run_id"]*="changed"
    @test_throws ErrorException build_r7_thermal_reconstruction(c, badr, s)
    altered=deepcopy(a)
    altered["values"]["out_S"]["data"][1]+=1.0
    @test !validate_r7_thermal_reconstruction(c, r, s, altered)["thermal_model_pass"]
    mktempdir() do dir
        dest=joinpath(dir, "run")
        save_r7_thermal_reconstruction(c, r, s, a, dest)
        @test read_r7_thermal_reconstruction(dest).validation["same_dispatch_pass"]
        @test_throws ErrorException save_r7_thermal_reconstruction(c, r, s, a, dest)
        open(joinpath(dest, "result.toml"), "a") do io
            write(io, "\n# altered\n")
        end
        @test_throws ErrorException read_r7_thermal_reconstruction(dest)
    end
    # R7-T5：原手算故障解源出力为零而循环流为正；原端口包络遗漏供回温区间产生的正下界。
    hc=load_r7_recovery_case(joinpath(R7THERM_ROOT, "configs/r7/recovery-hand.toml"))
    hr=solve_r7_recovery(hc, [1]; optimizer = opt, budget_sec = 60)
    hs=r7_thermal_spec(
        hc,
        hr;
        profiles = :uniform,
        profile_origin = "explicit old uniform assumption",
    )
    @test any(x->x["kind"]=="source_minimum_heat", r7_thermal_port_witness(hc, hr, hs))
    fail=solve_r7_thermal_reconstruction(hc, hr, hs; optimizer = opt, budget_sec = 60)
    @test fail["status"]=="infeasible_certified"
    @test !fail["validation"]["thermal_model_pass"]
    bad=deepcopy(fail)
    bad["termination_status"]="TIME_LIMIT"
    @test_throws ErrorException validate_r7_thermal_reconstruction(hc, hr, hs, bad)
    missing=solve_r7_thermal_reconstruction(
        c,
        r,
        s;
        optimizer = ()->error("license unavailable test stub"),
        budget_sec = 60,
    )
    @test missing["status"]=="license_unavailable"
    @test !missing["validation"]["thermal_model_pass"]
end

@testset "R7-T spatial memory and refinement" begin
    opt=optimizer_with_attributes(HiGHS.Optimizer, "threads"=>1)
    c, r=thermal_test_parent("thermal-front")
    @test r["validation"]["model_pass"]
    @test abs(r["validation"]["loss_MWh"])<=1e-6
    for n in (1, 4, 16)
        hot=thermal_front_spec(c, r, true; substeps = n)
        cold=thermal_front_spec(c, r, false; substeps = n)
        fake=deepcopy(hot)
        fake["uniform_assumption"]=true
        @test_throws ErrorException build_r7_thermal_reconstruction(c, r, fake)
        for side in ("S", "R")
            x=PaperRebuild.r7_thermal_inputs(c, r, hot)
            y=PaperRebuild.r7_thermal_inputs(c, r, cold)
            @test r7_pipe_inventory(x.states[(1, side, 1)]; cp_J_kgK = 4200, reference_K = 293.15)==r7_pipe_inventory(
                y.states[(1, side, 1)];
                cp_J_kgK = 4200,
                reference_K = 293.15,
            )
        end
        a=solve_r7_thermal_reconstruction(c, r, hot; optimizer = opt, budget_sec = 60)
        b=solve_r7_thermal_reconstruction(c, r, cold; optimizer = opt, budget_sec = 60)
        @test a["validation"]["same_dispatch_pass"]
        @test b["status"]=="infeasible_certified"
        cold["mode"]="curtail_heat"
        z=solve_r7_thermal_reconstruction(c, r, cold; optimizer = opt, budget_sec = 60)
        @test z["validation"]["thermal_model_pass"]
        @test !z["validation"]["same_dispatch_pass"]
        @test z["validation"]["conditional_heat_optimality_pass"]
        @test z["validation"]["heat_unserved_MWh"]≈1/30 atol=1e-6
    end
end

@testset "R7-T signed, stopped and lossy affine transport" begin
    c, r=thermal_test_parent("thermal-steady")
    s=r7_thermal_spec(c, r; profiles = :uniform, profile_origin = "affine operator test")
    x=PaperRebuild.r7_thermal_inputs(c, r, s)
    h=deepcopy(x.h)
    h["ambient_K"]=[290.0, 291.0, 292.0]
    h["pipes"][1]["UA_S_W_K"]=12.0
    v=deepcopy(x.v)
    v["m_pipe"]=reshape([2.0, -1.5, 0.0], 1, 3)
    x=merge(x, (; K = 3, T = 3, n = 1, h, v))
    map=PaperRebuild.r7_thermal_pipe_map(x, 1, "S", 1)
    for input in ([342.0, 336.0, 345.0], [350.0, 347.0, 340.0])
        y=PaperRebuild.r7_thermal_samples(
            PaperRebuild.r7_thermal_pipe_replay(x, 1, "S", 1, input),
            x,
            "S",
        )
        @test maximum(abs.(map.A*input+map.b-y))<1e-8
    end
    @test PaperRebuild.r7_thermal_ends(h["pipes"][1], "S", -1)==(2, 1)
    @test PaperRebuild.r7_thermal_ends(h["pipes"][1], "R", -1)==(1, 2)
end
