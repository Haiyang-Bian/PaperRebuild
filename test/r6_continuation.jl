module R6ContinuationTests
using Test
include(joinpath(@__DIR__, "..", "scripts", "continue_r6_study.jl"))

function fixture(dir, text; rule = 1)
    mkpath(dir)
    mktempdir() do tree
        file=joinpath(tree, "src", "core", "r6_evaluation.jl")
        mkpath(dirname(file))
        write(file, text)
        Tar.create(tree, joinpath(dir, "source.tar"))
    end
    m=Dict{String,Any}(
        "sources"=>Dict("src/core/r6_evaluation.jl"=>bytes2hex(sha256(text))),
        "archive_sha256"=>r6_study_hash(joinpath(dir, "source.tar")),
    )
    for field in (
        "spec",
        "spec_sha256",
        "physical_sha256",
        "protocol_sha256",
        "cases",
        "sets",
        "stress_sha256",
        "data_manifest_sha256",
    )
        m[field]=rule
    end
    r6_study_new(joinpath(dir, "freeze.toml"), m)
    write(joinpath(dir, "freeze.sha256"), r6_study_hash(joinpath(dir, "freeze.toml"))*"\n")
end

@testset "R6 continuation allows only byte-identical hash carrier change" begin
    mktempdir() do root
        old=joinpath(root, "old")
        new=joinpath(root, "new")
        fixture(old, "before\n"*R6_HASH_OLD*"\nafter\n")
        fixture(new, "before\n"*R6_HASH_NEW*"\nafter\n")
        @test r6_continuation_source_check(old, new).old["spec"]==1
        changed=joinpath(root, "rule_changed")
        fixture(changed, "before\n"*R6_HASH_NEW*"\nafter\n"; rule = 2)
        @test_throws ErrorException r6_continuation_source_check(old, changed)
        changed=joinpath(root, "source_changed")
        fixture(changed, "before\n"*R6_HASH_NEW*"\nmodel_changed\n")
        @test_throws ErrorException r6_continuation_source_check(old, changed)
        changed=joinpath(root, "no_change")
        fixture(changed, "before\n"*R6_HASH_OLD*"\nafter\n")
        @test_throws ErrorException r6_continuation_source_check(old, changed)
        write(joinpath(new, "source.tar"), "broken")
        @test_throws ErrorException r6_continuation_source_check(old, new)
    end
end
end
