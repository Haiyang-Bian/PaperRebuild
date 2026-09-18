using Test, TOML, SHA

"""
检查(5-91)/(5-92)的条件割在负补救费用下的最小反例。
仅验证分支下界代数和二进制乘积，不实现市场调度或Benders外层。
"""
function audit_ch05_cuts()
    witnesses=NamedTuple[]
    lower=-3.0
    @testset "R5-B01/B02 conditional cuts with negative recourse" begin
        for x in (0.0, 0.25, 0.5, 0.75, 1.0), z in (0, 1)
            q0, q1=1-x, -2-x
            q=z==0 ? q0 : q1
            literal=max(q0*(1-z), q1*z)
            checked=max(lower+(q0-lower)*(1-z), lower+(q1-lower)*z)
            @test q>=lower
            @test checked==q
            @test (q>=literal)==(z==0)
            push!(witnesses, (; x, z, recourse = q, literal, checked))
        end
        # 二进制乘积w=a*b的四行包络：在b=0/1时区间收缩到真实乘积。
        for a in (-2.0, -1.0, 0.0, 1.0, 2.0), b in (0, 1)
            lo, hi=-2.0, 2.0
            envelope_lo=max(lo*b, a-hi*(1-b))
            envelope_hi=min(hi*b, a-lo*(1-b))
            @test envelope_lo==envelope_hi==a*b
        end
        # 连续b时不是等式：a=0,b=.5仍允许w∈[-1,1]。
        @test max(-2*0.5, 0-2*(1-0.5))<0<min(2*0.5, 0+2*(1-0.5))
    end
    length(ARGS)<=1 || error("参数：[新的proof.toml]")
    if !isempty(ARGS)
        path=only(ARGS)
        ispath(path) && error("不覆盖已有条件割证据")
        mkpath(dirname(path))
        evidence=Dict(
            "schema"=>"r5-conditional-cut-audit-v1",
            "origin"=>"synthetic_analytic",
            "source_pages"=>[95],
            "scope"=>"Negative-recourse conditional-cut algebra and binary product only; no implemented Benders or convergence claim.",
            "script_sha256"=>bytes2hex(sha256(read(@__FILE__))),
            "julia"=>string(VERSION),
            "lower_bound"=>lower,
            "records"=>[Dict(string(k)=>v for (k, v) in pairs(r)) for r in witnesses],
        )
        open(path, "w") do io
            TOML.print(io, evidence; sorted = true)
        end
    end
end
audit_ch05_cuts()
