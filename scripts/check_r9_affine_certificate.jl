# 独立验证每个证书系数确实来自冻结模型，再用有理数重算推导，不调用优化器。
using Test, JuMP, TOML, CSV
include("r9_pv_study.jl")
decode_binary(text) = reinterpret(Float64, parse(UInt64, text; base = 16))
to_rational(text) = Rational{BigInt}(decode_binary(text))
function check_affine_certificate(batch, audit, output)
    ispath(output) && error("不覆盖证书重验")
    meta = TOML.parsefile(joinpath(audit, "audit.toml"))
    cert = TOML.parsefile(joinpath(audit, "certificate.toml"))
    f = R9PVStudy.frozen(batch)
    meta["parent_manifest_sha256"] == R9PVStudy.hashfile(joinpath(batch, "manifest.toml")) ||
        error("父证据改变")
    b = Base.invokelatest(
        () ->
            getfield(f.mod, :build_r9_pv_model)(f.c; mode = Symbol(get(meta, "mode", "CF_CT"))),
    )
    refs = all_constraints(b.model, AffExpr, MOI.EqualTo{Float64})
    allvars = Dict(index(x).value => x for x in all_variables(b.model))
    labels = Dict{Int,String}()
    for (key, array) in b.variables, idx in CartesianIndices(array)
        x = array[idx]
        x isa VariableRef && (labels[index(x).value] = key*"["*join(Tuple(idx), ",")*"]")
    end
    ids = Dict(cr => id for (id, rows) in b.constraints for cr in rows)
    known = Dict{Int,Rational{BigInt}}()
    display_rows = NamedTuple[]
    residual = Rational{BigInt}(0)
    @testset "R9 exact binary certificate and original-row identity" begin
        @test cert["schema"] == "r9-affine-rational-certificate-v1"
        @test f.c.sha256 == meta["input_sha256"]
        for row in cert["fixed"]
            x, v = row["variable"], row["value_ieee754"]
            @test is_fixed(allvars[x])
            @test reinterpret(UInt64, fix_value(allvars[x])) == parse(UInt64, v; base = 16)
            known[x] = to_rational(v)
        end
        for (step, row) in enumerate([cert["steps"]; cert["contradiction"]])
            cr = refs[row["model_equation_index"]]
            obj = constraint_object(cr)
            @test constant(obj.func) == 0
            @test Rational{BigInt}(obj.set.value) == to_rational(row["rhs_ieee754"])
            actual = Dict(
                index(x).value => Rational{BigInt}(a) for
                (a, x) in linear_terms(obj.func) if a != 0
            )
            coeffs = Dict(
                x => to_rational(a) for
                (x, a) in zip(row["variables"], row["coefficients_ieee754"])
            )
            @test actual == coeffs
            variable = row["derived_variable"]
            @test all(haskey(known, x) || x == variable for x in keys(coeffs))
            remaining =
                to_rational(row["rhs_ieee754"]) -
                sum(a*known[x] for (x, a) in coeffs if x != variable; init = Rational{BigInt}(0))
            if variable == 0
                @test remaining != 0
                residual = remaining
            else
                @test !haskey(known, variable)
                known[variable] = remaining/coeffs[variable]
            end
            push!(
                display_rows,
                (
                    step,
                    equation = get(ids, cr, "variable_equality"),
                    derived_variable = variable == 0 ? "contradiction" :
                                       get(labels, variable, "aux_"*string(variable)),
                    terms = join(
                        [
                            string(Float64(a))*" * "*get(labels, x, "aux_"*string(x)) for
                            (x, a) in sort(collect(coeffs))
                        ],
                        " + ",
                    ),
                    rhs = decode_binary(row["rhs_ieee754"]),
                    derived_or_residual_value = Float64(
                        variable == 0 ? remaining : known[variable],
                    ),
                ),
            )
        end
    end
    mkpath(output)
    CSV.write(joinpath(output, "derivation.csv"), display_rows)
    summary = Dict(
        "schema"=>"r9-affine-certificate-check-v1",
        "input_sha256"=>f.c.sha256,
        "certificate_sha256"=>R9PVStudy.hashfile(joinpath(audit, "certificate.toml")),
        "fixed_count"=>length(cert["fixed"]),
        "derived_count"=>length(cert["steps"]),
        "contradiction_residual"=>Float64(residual),
        "exact_numerator"=>string(numerator(residual)),
        "exact_denominator"=>string(denominator(residual)),
        "original_row_identity_pass"=>true,
    )
    write(joinpath(output, "check.toml"), R9PVStudy.textfile(summary))
    cp(@__FILE__, joinpath(output, "checker-source.jl"))
    println(summary)
end
length(ARGS) == 3 || error("usage: check_r9_affine_certificate.jl BATCH AUDIT NEW_OUTPUT")
check_affine_certificate(ARGS...)
