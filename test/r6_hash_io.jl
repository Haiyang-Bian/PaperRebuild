module R6HashIOTests
using Test, SHA, TOML, PaperRebuild

@testset "R6 UTF-8 digest identity and existing policy identity" begin
    # IOBuffer只改变送入SHA的载体，不改变UTF-8字节、序列化、算法或原有摘要。
    for n in (0, 1, 63, 64, 65, 1024, 65536)
        for text in (repeat("x", n), repeat("温度α\n", n))
            @test sha256(IOBuffer(text))==sha256(Vector{UInt8}(codeunits(text)))
            n<=1024 && @test sha256(IOBuffer(text))==sha256(text)
        end
    end
    @test bytes2hex(sha256(IOBuffer("abc")))=="ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    root=normpath(joinpath(@__DIR__, ".."))
    pilot=joinpath(root, "results", "summaries", "r6-training-pilot-v1", "witnesses", "D.toml")
    w=TOML.parsefile(pilot)
    c=R5StrategicCase(w["case"])
    text=PaperRebuild.r5_market_text(w["result"])
    p=load_r6_physical_case(joinpath(root, "configs", "r6", "daily-small.toml"))
    policy=r6_policy_from_training(p, c, w["result"])
    @test policy.data["award"]["parent_result_sha256"]==bytes2hex(sha256(text))
    @test policy.data["award"]["parent_run_id"]==w["result"]["run_id"]
end
end
