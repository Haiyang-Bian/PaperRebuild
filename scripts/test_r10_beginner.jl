using Test, TOML
include("r10_beginner_evidence.jl")
const R10E = R10BeginnerEvidence
length(ARGS) == 1 || error("Usage: test_r10_beginner.jl BUNDLE")
original = abspath(ARGS[1])

@testset "R10 immutable and independent beginner replay" begin
    report = R10E.check(original)
    @test report["model_pass"] && report["original_branch_pass"]
    @test report["objective"] ≈ 24.33235889299821 atol = 1e-10
    @test !any(p -> p.name in ("JuMP", "Gurobi", "Clarabel"), keys(Base.loaded_modules))
    mktempdir() do dir
        moved = joinpath(dir, "moved")
        cp(original, moved)
        @test R10E.check(moved) == report
        path = joinpath(moved, "run", "solution.toml")
        open(io -> write(io, "\n# tamper\n"), path, "a")
        @test_throws ErrorException R10E.check(moved)
    end
    mktempdir() do dir
        moved = joinpath(dir, "resigned")
        cp(original, moved)
        path = joinpath(moved, "run", "solution.toml")
        value = TOML.parsefile(path)
        value["values"]["P_grid"][1] += 0.01
        R10E.write_toml(path, value)
        meta_path = joinpath(moved, "run", "metadata.toml")
        meta = TOML.parsefile(meta_path)
        meta["solution_sha256"] = R10E.sha(path)
        R10E.write_toml(meta_path, meta)
        R10E.sign(moved)
        # 哈希重新签写也不能掩盖守恒错误；此时应由独立方程检查拒绝。
        err = try
            R10E.check(moved)
            nothing
        catch e
            e
        end
        @test err isa ErrorException
        @test occursin("Independent physical replay failed", sprint(showerror, err))
    end
    @test_throws ErrorException R10E.safe(original, "../outside")
    @test_throws ErrorException R10E.archive(original, original)
end
