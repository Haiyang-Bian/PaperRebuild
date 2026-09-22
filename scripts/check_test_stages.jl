# 只读解析实际测试入口，检查CI分组并集；不执行科学测试或任意AST。
using Test

const STAGE_ROOT=normpath(joinpath(@__DIR__, ".."))

function stage_include_path(x)
    x isa String && return normpath(joinpath(STAGE_ROOT, "test", x))
    x isa Expr && x.head==:call && x.args[1]==:joinpath || error("Unknown include path")
    a=x.args[2:end]
    a[1] isa Expr && a[1].head==:macrocall && a[1].args[1]==Symbol("@__DIR__") ||
        error("Include path must start in test directory")
    all(y->y isa String, a[2:end]) || error("Nonliteral include path")
    normpath(joinpath(STAGE_ROOT, "test", a[2:end]...))
end

function stage_paths(stage)
    paths=String[]
    for node in Meta.parseall(read(joinpath(STAGE_ROOT, "test/runtests.jl"), String)).args
        node isa Expr && node.head==:if || continue
        length(node.args)==2 || error("Unexpected test branch")
        cond, body=node.args
        cond isa Expr &&
        cond.head==:call &&
        cond.args[1]==:in &&
        cond.args[2]==:PAPERREBUILD_TEST_STAGE &&
        cond.args[3].head==:tuple || error("Unknown stage condition")
        stage in cond.args[3].args || continue
        for row in body.args
            row isa LineNumberNode && continue
            row isa Expr && row.head==:call && row.args[1]==:include && length(row.args)==2 ||
                error("Test branches must contain explicit includes")
            push!(paths, stage_include_path(row.args[2]))
        end
    end
    paths
end

@testset "CI stages cover the full test entry without omissions or duplicates" begin
    full=stage_paths("all")
    ci=read(joinpath(STAGE_ROOT, ".github/workflows/ci.yml"), String)
    stage_line=only(collect(eachmatch(r"(?m)^\s+stage: \[([^\]]+)\]", ci)))
    stages=strip.(split(stage_line.captures[1], ','))
    parts=[stage_paths(s) for s in stages]
    @test all(!isempty, parts)
    @test length(full)==length(unique(full))
    @test all(isfile, full)
    @test sort(vcat(parts...))==sort(full)
    @test sort(stage_paths("r7_r9"))==sort(
        vcat(stage_paths.(["r7_r8", "r9_physics", "r9_markets"])...),
    )
    println("CI stages: ", join(stages, ", "), "; test files: ", length(full))
end
