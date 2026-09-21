using Test, PaperRebuild, SHA

@testset "R5 risk canonical row ordering retains exact legacy bytes" begin
    legacy(x) =
        if x isa AbstractDict
            d=Dict{String,Any}(string(k)=>legacy(v) for (k, v) in x)
            haskey(d, "rows") && sort!(d["rows"]; by = PaperRebuild.r5_market_text)
            d
        elseif x isa AbstractVector
            legacy.(x)
        else
            x
        end
    a=Dict("id"=>"中文/α", "residual"=>1e-8, "pass"=>true)
    b=Dict("id"=>"b/2", "residual"=>-0.0, "pass"=>false)
    for rows in (Any[], [a], [a, b, a, b], reverse([a, b]))
        v=Dict("rows"=>rows, "nested"=>Dict("rows"=>reverse(rows)))
        previous=PaperRebuild.r5_market_text(legacy(v))
        @test PaperRebuild.r5_risk_validation_text(v)==previous
        @test PaperRebuild.r5_risk_validation_text(v)==PaperRebuild.r5_risk_validation_text(
            deepcopy(v),
        )
    end
end
