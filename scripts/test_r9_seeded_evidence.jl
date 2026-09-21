using Test, TOML
include("seal_r9_seeded.jl")
const E=R9SeededEvidence
length(ARGS)==3 || error("usage: COMMON_INPUT FREEZE EVIDENCE")
common, frozen, evidence=abspath.(ARGS)
@testset "R9 seeded portable original-value replay and false-success rejection" begin
    mktempdir() do root
        a, b, c=joinpath.(root, ("common", "seeded", "evidence"))
        cp(common, a)
        cp(frozen, b)
        cp(evidence, c)
        @test E.check(a, b, c; replay = true)
        m=TOML.parsefile(joinpath(c, "delivery.toml"))
        rel="3A/status.toml"
        path=joinpath(c, rel)
        old=read(path)
        open(io->write(io, "# altered"), path, "a")
        @test_throws ErrorException E.check(a, b, c; replay = false)
        write(path, old)
        function mutate!(f)
            data=TOML.parsefile(path)
            f(data)
            E.toml(path, data)
            mm=deepcopy(m)
            mm["files"][rel]=E.hashfile(path)
            E.toml(joinpath(c, "delivery.toml"), mm)
        end
        for f in (
            d->(d["budget_pass"]=!d["budget_pass"]),
            d->(d["model_pass"]=!d["model_pass"]),
            d->(d["has_candidate"]=!d["has_candidate"]),
            d->(d["cost_optimization_complete"]=!d["cost_optimization_complete"]),
            d->(d["case_sha256"]="incorrect"),
            d->(d["parent_witness_sha256"]="incorrect"),
        )
            mutate!(f)
            @test_throws ErrorException E.check(a, b, c; replay = false)
            write(path, old)
            E.toml(joinpath(c, "delivery.toml"), m)
        end
        @test E.check(a, b, c; replay = false)
    end
end
