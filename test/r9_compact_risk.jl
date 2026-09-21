module R9CompactRiskTests
using Test, PaperRebuild, JuMP, HiGHS, TOML
const PR=PaperRebuild
const ROOT=dirname(@__DIR__)
opt=optimizer_with_attributes(
    HiGHS.Optimizer,
    "threads"=>1,
    "output_flag"=>false,
    "mip_rel_gap"=>1e-9,
)

# 消去新增费用变量后逐行比較，不以最优目标碰巧相同代替模型等价。
function normal(expr, aliases)
    out=AffExpr(0.0)
    src=expr isa VariableRef ? AffExpr(0.0, expr=>1.0) : expr
    out.constant=src.constant
    for (v, a) in src.terms
        add_to_expression!(out, a, get(aliases, v, v))
    end
    coeff=sort!([(name(v), a) for (v, a) in out.terms if !iszero(a)])
    (out.constant, coeff)
end
function rows(b; compact = false)
    aliases=compact ? Dict(zip(b.cost_alias.variables, b.cost_alias.expressions)) : Dict()
    omit=compact ? Set(b.cost_alias.rows) : Set()
    counts=Dict{Any,Int}()
    for (F, S) in list_of_constraint_types(b.model), ref in all_constraints(b.model, F, S)
        ref in omit && continue
        obj=constraint_object(ref)
        c, a=normal(obj.func, aliases)
        rhs=obj.set isa MOI.LessThan ? obj.set.upper :
            obj.set isa MOI.GreaterThan ? obj.set.lower :
            obj.set isa MOI.EqualTo ? obj.set.value : 0.0
        key=(string(S), rhs-c, a)
        counts[key]=get(counts, key, 0)+1
    end
    counts
end
@testset "R9-CX1:CX3 exact rows, objectives and bidirectional points" begin
    for file in ("hard_zero", "hard_r100", "thermal_e030_r005")
        c=load_r5_risk_case(joinpath(ROOT, "configs/r5/risk", file*".toml"))
        for pattern in (nothing, zeros(Int, length(c.data["commitment"]["scenarios"])))
            old=build_r5_risk(c; optimizer = opt, pattern)
            new=PR.build_r9_compact_risk(c; optimizer = opt, pattern)
            @test rows(old)==rows(new; compact = true)
            @test normal(objective_function(old.model), Dict())==normal(
                objective_function(new.model),
                Dict(),
            )
            optimize!(old.model)
            optimize!(new.model)
            @test termination_status(old.model)==termination_status(new.model)==MOI.OPTIMAL
            @test objective_value(old.model)≈objective_value(new.model) atol=1e-7
            oldvals=Dict(name(v)=>value(v) for v in all_variables(old.model))
            newvals=Dict(name(v)=>value(v) for v in all_variables(new.model))
            @test audit_r9_risk_start(old, [newvals[name(v)] for v in all_variables(old.model)])["pass"]
            for (v, expr) in zip(new.cost_alias.variables, new.cost_alias.expressions)
                oldvals[name(v)]=value(v->oldvals[name(v)], expr)
            end
            @test audit_r9_risk_start(new, [oldvals[name(v)] for v in all_variables(new.model)])["pass"]
            @test num_variables(new.model)==num_variables(old.model)+length(new.q)
            println(file, " pattern=", pattern!==nothing, " objective=", objective_value(new.model))
        end
    end
end
@testset "R9-CX1:CX3 bounds, small coefficients and complete initial point" begin
    m=Model()
    @variable(m, x)
    bad=(bound = false, coefficients = Dict("x"=>1.0), rhs = 0.0, sense = :ge)
    @test_throws ErrorException PR.r9_compact_bound!(x, bad)
    for patch in (
        (bound = true, sense = :eq),
        (bound = true, rhs = Inf),
        (bound = true, coefficients = Dict("x"=>-1.0)),
    )
        @test_throws ErrorException PR.r9_compact_bound!(x, merge(bad, patch))
    end
    @test !has_lower_bound(x) && !has_upper_bound(x)
    PR.r9_compact_bound!(x, merge(bad, (bound = true,)))
    @test lower_bound(x)==0.0
    @test_throws ErrorException PR.r9_compact_bound!(x, merge(bad, (bound = true,)))
    expr=PR.r9_compact_affine(Dict("x"=>1e-30), Dict("x"=>x))
    @test coefficient(expr, x)==1e-30
    c=load_r5_risk_case(joinpath(ROOT, "configs/r5/risk/hard_zero.toml"))
    before=deepcopy(c.data)
    w=solve_r9_common_witness(c; optimizer = opt, budget_sec = 30)
    for pattern in (nothing, zeros(Int, length(c.data["commitment"]["scenarios"])))
        b=PR.build_r9_compact_risk(c; pattern)
        point=r9_risk_start_values(c, b, w)
        @test audit_r9_risk_start(b, point)["pass"]
        @test length(point)==num_variables(b.model) && all(isfinite, point)
    end
    @test c.data==before
end

include(joinpath(ROOT, "scripts/r9_seeded_study.jl"))
const SS=R9SeededStudy
function start_values!(m, point; lp)
    for (v, a) in zip(all_variables(m), point)
        set_start_value(v, a)
    end
    Dict("variables"=>length(point), "test_adapter"=>true, "lp"=>lp)
end
@testset "R9-CX1:CX3 original verifier, archive and failure propagation" begin
    c=load_r5_risk_case(joinpath(ROOT, "configs/r5/risk/hard_zero.toml"))
    w=solve_r9_common_witness(c; optimizer = opt, budget_sec = 30)
    for pattern in (nothing, zeros(Int, 3))
        r=solve_r9_seeded_risk(
            c,
            w;
            optimizer = opt,
            seed! = start_values!,
            oracle_optimizer = opt,
            pattern,
            budget_sec = 60,
            representation = :r9_compact_v1,
        )
        @test r["status"]=="solver_optimal" && r["has_candidate"]
        @test all(
            r["validation"][k] for k in ("model_pass", "risk_pass", "cost_pass", "optimality_pass")
        )
        @test r["cost_optimization_complete"] && r["initial_point_audit"]["pass"]
        @test r["solver_objective"]≈2.085 atol=1e-7
        @test r["source_hashes_at_solve"]==PR.r5_risk_science_hashes()
        @test r["representation_statistics"]["cost_alias_equalities"]==3
        @test length(r["representation_source_hashes"])==2
        mktempdir() do dir
            path=joinpath(dir, "run")
            SS.save_numeric(path, r)
            rr=SS.read_numeric(path)
            @test rr.result["representation"]=="r9_compact_v1"
            @test rr.result["first_stage"]==r["first_stage"] &&
                  rr.result["scenarios"]==r["scenarios"]
            @test rr.validation==SS.compact_validation(validate_r5_risk(c, rr.result))
            open(io->write(io, "# modified"), joinpath(path, "result.toml"), "a")
            @test_throws ErrorException SS.read_numeric(path)
        end
    end
    tiny=solve_r9_seeded_risk(
        c,
        w;
        optimizer = opt,
        seed! = start_values!,
        oracle_optimizer = opt,
        representation = :r9_compact_v1,
        budget_sec = 1e-12,
    )
    @test tiny["status"]=="budget_exhausted_before_build" && !tiny["has_candidate"]
    failed=solve_r9_seeded_risk(
        c,
        w;
        optimizer = opt,
        seed! = (args...; kwargs...)->error("license unavailable"),
        oracle_optimizer = opt,
        representation = :r9_compact_v1,
        budget_sec = 30,
    )
    @test failed["status"]=="license_unavailable" && !haskey(failed, "first_stage")
    @test_throws ErrorException solve_r9_seeded_risk(
        c,
        w;
        optimizer = opt,
        seed! = start_values!,
        oracle_optimizer = opt,
        representation = :changed_physics,
    )
    @test_throws ErrorException solve_r9_seeded_risk(
        c,
        w;
        optimizer = opt,
        seed! = start_values!,
        oracle_optimizer = opt,
        solver_log = "yes",
    )
    # 日志接口与原状态定义保持一致，过期截止时间不启动求解。
    m=Model(opt)
    @variable(m, x>=2)
    @objective(m, Min, x)
    logged=PR.r9_logged_risk_optimize!(m, time()+30)
    @test logged["status"]=="solver_optimal" && logged["solver_objective"]==2
    @test logged["solver_logging_requested"]
    @test PR.r9_logged_risk_optimize!(m, time()-1)["status"]=="budget_exhausted_before_solve"
end

end
