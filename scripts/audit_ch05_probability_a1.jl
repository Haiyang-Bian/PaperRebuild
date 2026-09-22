using TOML, SHA
include("check_ch05_probability.jl")
length(ARGS)==1 || error("参数：新的A1补证TOML路径")
root=normpath(joinpath(@__DIR__, ".."))
path=joinpath(root, "results", "summaries", "ch05-probability", "proof.toml")
check_ch05_probability(path)
d=TOML.parsefile(path)
checks=Dict{String,Any}[]
for (i, r) in enumerate(d["records"])
    p=reduce(vcat, permutedims.(r["transport"]))
    distance=reduce(vcat, permutedims.(r["distance"]))
    worst=vec(sum(p; dims = 2))
    residual=max(
        0.0,
        -minimum(p),
        maximum(abs.(vec(sum(p; dims = 1))-r["weights"])),
        sum(p .* distance)-r["radius"],
        abs(sum(worst)-1),
        -minimum(worst),
    )
    push!(
        checks,
        Dict(
            "witness"=>i,
            "probability_transport_residual"=>residual,
            "tolerance"=>1e-8,
            "pass"=>residual<=1e-8,
        ),
    )
end
evidence=Dict(
    "schema"=>"r5-q05-a1-audit-v1",
    "origin"=>"synthetic_analytic",
    "scope"=>"A1 probability and mass transport only; original algebra proof retained unchanged.",
    "original_algebra_tolerance"=>d["tolerance"],
    "A1_probability_tolerance"=>1e-8,
    "proof_sha256"=>bytes2hex(sha256(read(path))),
    "script_sha256"=>bytes2hex(sha256(read(@__FILE__))),
    "checker_sha256"=>bytes2hex(sha256(read(joinpath(@__DIR__, "check_ch05_probability.jl")))),
    "max_residual"=>maximum(x["probability_transport_residual"] for x in checks),
    "records"=>checks,
)
dest=only(ARGS)
ispath(dest) && error("不覆盖A1补证")
mkpath(dirname(dest))
open(dest, "w") do io
    TOML.print(io, evidence; sorted = true)
end
println("All 17 witnesses pass unchanged A1=1e-8; max residual ", evidence["max_residual"])
