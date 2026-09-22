using Test, TOML, SHA
include("r9_block_bound_evidence.jl")
const B=R9BlockBoundEvidence

function poly(;
    constant = 0.0,
    ids = Int[],
    coefficients = Float64[],
    qi = Int[],
    qj = Int[],
    qc = Float64[],
)
    Dict(
        "constant"=>constant,
        "linear_ids"=>ids,
        "linear_coefficients"=>coefficients,
        "quadratic_i"=>qi,
        "quadratic_j"=>qj,
        "quadratic_coefficients"=>qc,
    )
end
unit(i) = poly(; ids = [i], coefficients = [1.0])
row(id, kind, functions; rhs = 0.0) =
    Dict("id"=>id, "kind"=>kind, "functions"=>functions, "rhs"=>rhs)

@testset "R9 block numeric replay: analytic QP signs and RSOC" begin
    p=poly(; ids = [1], coefficients = [2.0], qi = [1, 1], qj = [1, 2], qc = [3.0, 4.0])
    @test B.polynomial(p, [2.0, 3.0])==(40.0, [26.0, 8.0])
    for (kind, x, y, rhs) in
        (("lower", 1.0, 2.0, 1.0), ("upper", -1.0, -2.0, -1.0), ("equal", 1.0, 2.0, 1.0))
        s=Dict(
            "variables"=>["x"],
            "objective"=>poly(; qi = [1], qj = [1], qc = [1.0]),
            "constraints"=>[row("c", kind, [unit(1)]; rhs)],
        )
        w=Dict("x"=>[x], "reported_objective"=>1.0, "raw_duals"=>Dict("c"=>[y]))
        r=B.replay(s, w)
        @test all(
            r[k]==0 for k in (
                "primal_normalized",
                "dual_normalized",
                "stationarity_normalized",
                "complementarity_normalized",
            )
        )
        w["raw_duals"]["c"]=[-y]
        @test B.replay(s, w)["stationarity_normalized"]>1e-6
    end
    s=Dict(
        "variables"=>["w", "x"],
        "objective"=>unit(1),
        "constraints"=>[
            row("cone", "rsoc", [unit(1), poly(; constant = 0.5), unit(2)]),
            row("bound", "lower", [unit(2)]; rhs = 2.0),
        ],
    )
    w=Dict(
        "x"=>[4.0, 2.0],
        "reported_objective"=>4.0,
        "raw_duals"=>Dict("cone"=>[1.0, 8.0, -4.0], "bound"=>[4.0]),
    )
    r=B.replay(s, w)
    @test maximum(
        r[k] for k in (
            "primal_normalized",
            "dual_normalized",
            "stationarity_normalized",
            "complementarity_normalized",
        )
    )<=1e-14
    @test !r["global_bound_certified"] && r["diagnostic_only"]
    bad=deepcopy(w)
    bad["raw_duals"]["cone"][3]=-2.0
    @test B.replay(s, bad)["stationarity_normalized"]>1e-6
    bad=deepcopy(w)
    delete!(bad["raw_duals"], "cone")
    @test !B.replay(s, bad)["all_raw_duals_available"]
    @test isnan(B.replay(s, bad)["dual_normalized"])
    bad=deepcopy(w)
    bad["x"][1]=3.0
    @test B.replay(s, bad)["primal_normalized"]>1e-6
end

@testset "R9-DB1 exact bound representation: preserve every other row" begin
    old=Dict(
        "variables"=>["x"],
        "objective"=>unit(1),
        "constraints"=>[
            row("lo", "lower", [unit(1)]; rhs = 1.0),
            row("hi", "upper", [unit(1)]; rhs = 1.0),
        ],
    )
    new=deepcopy(old)
    new["constraints"]=[row("fixed", "equal", [unit(1)]; rhs = 1.0)]
    declaration=[Dict("index"=>1, "name"=>"x", "value"=>1.0)]
    @test B.equivalent(old, new, declaration)
    bad=deepcopy(new)
    bad["constraints"][1]["rhs"]=1.000001
    @test_throws ErrorException B.equivalent(old, bad, declaration)
    bad=deepcopy(old)
    bad["constraints"][2]["rhs"]=1.000001
    @test_throws ErrorException B.equivalent(bad, new, declaration)
    @test_throws ErrorException B.equivalent(old, new, [declaration; declaration])
end

if !isempty(ARGS)
    @testset "R9 four saved block witnesses: relocated and tamper checks" begin
        path=ARGS[1]
        @test length(B.check(path))==4
        mktempdir() do temporary
            moved=joinpath(temporary, "evidence")
            cp(path, moved)
            @test length(B.check(moved))==4
            target=joinpath(moved, "Clarabel_exact_fix", "model.toml")
            d=TOML.parsefile(target)
            d["objective"]["constant"]+=1.0
            B.write_toml(target, d)
            @test_throws ErrorException B.check(moved)
            manifest=joinpath(moved, "artifact-hashes.toml")
            hashes=TOML.parsefile(manifest)
            hashes["files"]["Clarabel_exact_fix/model.toml"]=B.hashfile(target)
            B.write_toml(manifest, hashes)
            @test_throws ErrorException B.check(moved)
        end
    end
end
