using Test, TOML, SHA
include("r9_reserve_study.jl")
length(ARGS)==1 || error("usage: test_r9_reserve_freeze.jl STUDY")
source=abspath(ARGS[1])
@testset "R9 frozen training identities, portable source and tamper rejection" begin
    bundle=R9ReserveStudy.check(source)
    @test [length(bundle.dataset.sets[s].ids) for s in ("train", "validation", "test")]==[2000, 500, 1000]
    @test bundle.dataset.representatives["converged"]
    @test !bundle.manifest["optimization_performed_at_freeze"]
    for e in bundle.manifest["methods"]
        c=R9ReserveStudy.call(
            bundle.lib,
            :r9_reserve_risk_case,
            bundle.template,
            bundle.dataset.sets["train"],
            bundle.dataset.representatives,
            bundle.spec,
            e["scheme"];
            pilot = e["pilot"],
        )
        @test c.sha256==e["case_sha256"]
        @test length(c.data["commitment"]["scenarios"])==e["scenarios"]
    end
    mktempdir() do tmp
        moved=joinpath(tmp, "moved-study")
        cp(source, moved)
        reread=R9ReserveStudy.check(moved)
        @test reread.template.sha256==bundle.template.sha256
        @test reread.spec.sha256==bundle.spec.sha256
        p=joinpath(moved, "template.toml")
        original=read(p)
        write(p, vcat(original, codeunits("\n# byte tamper\n")))
        @test_throws ErrorException R9ReserveStudy.check(moved)
        write(p, original)
        write(joinpath(moved, "extra.txt"), "undeclared")
        @test_throws ErrorException R9ReserveStudy.check(moved)
    end
end
