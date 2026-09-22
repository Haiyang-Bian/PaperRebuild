using Test
include("r6_public_report.jl")

@testset "R6 portable evidence boundaries" begin
    for rel in ("../x", "a/../b", "C:/x", "a\\b", "/root", "a//b", "")
        @test_throws ErrorException r6_public_path(pwd(), rel)
    end
    @test r6_public_path(pwd(), "a/b") == joinpath(pwd(), "a", "b")
    @test isnothing(r6_public_equal(Dict("x"=>NaN), Dict("x"=>NaN)))
    @test_throws ErrorException r6_public_equal(Dict("pass"=>false), Dict("pass"=>true))
    @test_throws ErrorException r6_public_equal(Dict("n"=>1000), Dict("n"=>999))
    mktempdir() do dir
        write(joinpath(dir, "a.csv"), "original\n")
        m=Dict(
            "schema"=>"r6-public-evidence-v1",
            "origin"=>"synthetic",
            "test_physics_replayed_by_bundle"=>false,
            "stress_physics_replayed_by_bundle"=>true,
            "solver_reexecuted"=>false,
            "files"=>r6_public_inventory(dir),
        )
        function seal()
            write(joinpath(dir, "public.toml"), r6_public_text(m))
            write(joinpath(dir, "public.sha256"), r6_public_hash(joinpath(dir, "public.toml")))
        end
        seal()
        @test r6_public_manifest(dir)==m
        write(joinpath(dir, "a.csv"), "changed\n")
        @test_throws ErrorException r6_public_manifest(dir)
        write(joinpath(dir, "a.csv"), "original\n")
        m["test_physics_replayed_by_bundle"]=true
        seal()
        @test_throws ErrorException r6_public_manifest(dir)
        @test_throws ErrorException create_r6_public("missing", "missing", dir)
    end
end

# 正式证据可选：先做完整冻结重验，再验证重封哈希的伪造统计不能绕过数值检查。
if !isempty(ARGS)
    length(ARGS)==1 || error("至多一个正式证据路径")
    @testset "R6 saved public evidence" begin
        @test isnothing(check_r6_public(only(ARGS)))
        mktempdir() do tmp
            dir=joinpath(tmp, "altered")
            cp(only(ARGS), dir)
            report=TOML.parsefile(joinpath(dir, "tables/report.toml"))
            file=first(sort(filter(f->startswith(f, "days"), collect(keys(report["tables"])))))
            # Windows 的文件映射仍被 CSV.Row 引用时不能截断原路径；先读入内存再构造篡改副本。
            rows=collect(CSV.File(read(joinpath(dir, "tables", file))))
            changed=[
                i==1 ? merge(NamedTuple(r), (net_cost_USD = r.net_cost_USD+10,)) : NamedTuple(r) for
                (i, r) in enumerate(rows)
            ]
            CSV.write(joinpath(dir, "tables", file), changed)
            report["tables"][file]=r6_public_hash(joinpath(dir, "tables", file))
            write(joinpath(dir, "tables/report.toml"), r6_public_text(report))
            write(
                joinpath(dir, "tables/report.sha256"),
                r6_public_hash(joinpath(dir, "tables/report.toml")),
            )
            m=TOML.parsefile(joinpath(dir, "public.toml"))
            m["files"]=r6_public_inventory(dir)
            delete!(m["files"], "public.toml")
            delete!(m["files"], "public.sha256")
            m["report_sha256"]=r6_public_hash(joinpath(dir, "tables/report.toml"))
            write(joinpath(dir, "public.toml"), r6_public_text(m))
            write(joinpath(dir, "public.sha256"), r6_public_hash(joinpath(dir, "public.toml")))
            @test r6_public_manifest(dir)==m
            @test_throws ProcessFailedException check_r6_public(dir)
        end
    end
end
