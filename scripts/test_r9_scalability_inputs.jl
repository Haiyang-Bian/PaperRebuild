using Test, TOML, SHA
include("r9_scalability_inputs.jl")
using .R9ScalabilityInputs: safe, hashfile, toml, check
VERSION==v"1.12.6" || error("Use Julia 1.12.6")
length(ARGS)==1 || error("Usage: test_r9_scalability_inputs.jl PREPARED_DIRECTORY")
source=abspath(only(ARGS))
original=TOML.parsefile(safe(source, "manifest.toml"))

function with_copy(f)
    mktempdir(joinpath(dirname(@__DIR__), "tmp")) do out
        for rel in [collect(keys(original["files"])); "manifest.toml"]
            cp(safe(source, rel), safe(out, rel))
        end
        f(out)
    end
end

@testset "Prepared R9 split inputs: portable checks and resigned tamper" begin
    @test check(source)["optimization_performed"]==false
    with_copy() do out
        @test check(out)["files"]==original["files"]
    end
    with_copy() do out
        path=safe(out, "ag16.toml")
        open(io->write(io, "\n# changed\n"), path, "a")
        @test_throws ErrorException check(out)
    end
    with_copy() do out
        # 重新签全部文件哈希仍不能掩盖改变经济模型的不满意度参数。
        d=TOML.parsefile(safe(out, "ag16.toml"))
        d["actors"][2]["sat_P"]+=1
        toml(safe(out, "ag16.toml"), d)
        receipt=TOML.parsefile(safe(out, "ag16-mapping.toml"))
        receipt["child_sha256"]=hashfile(safe(out, "ag16.toml"))
        toml(safe(out, "ag16-mapping.toml"), receipt)
        m=deepcopy(original)
        for rel in ("ag16.toml", "ag16-mapping.toml")
            m["files"][rel]=hashfile(safe(out, rel))
        end
        toml(safe(out, "manifest.toml"), m)
        @test_throws ErrorException check(out)
    end
    with_copy() do out
        m=deepcopy(original)
        delete!(m["files"], "ag32-audit.toml")
        toml(safe(out, "manifest.toml"), m)
        @test_throws ErrorException check(out)
    end
end
