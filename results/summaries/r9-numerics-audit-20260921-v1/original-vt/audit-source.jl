# 从冻结原建模器的固定变量和线性等式提取精确矛盾；不求解、不改变模型。
using JuMP, TOML, SHA
include("r9_pv_study.jl")
bits(x::Float64) = string(reinterpret(UInt64, x); base = 16, pad = 16)
exact(x::Float64) = Rational{BigInt}(x)
function audit_affine_exact(batch, output, mode = "CF_CT")
    mode in ("CF_CT", "CF_VT") || error("未知固定流量模式")
    ispath(output) && error("不覆盖原式精确审计")
    start = time()
    f = R9PVStudy.frozen(batch)
    b = Base.invokelatest(() -> getfield(f.mod, :build_r9_pv_model)(f.c; mode = Symbol(mode)))
    model = b.model
    fixed = Dict(index(x).value => exact(fix_value(x)) for x in all_variables(model) if is_fixed(x))
    fixed_bits = Dict(index(x).value => bits(fix_value(x)) for x in all_variables(model) if is_fixed(x))
    known = copy(fixed)
    equations = []
    for cr in all_constraints(model, AffExpr, MOI.EqualTo{Float64})
        obj = constraint_object(cr)
        constant(obj.func) == 0 || error("须单独处理未归一化常数，禁止引入新舍入")
        push!(equations, (rhs = exact(obj.set.value - constant(obj.func)),
            rhs_bits = bits(obj.set.value - constant(obj.func)),
            terms = [(index(x).value, exact(a), bits(a)) for (a,x) in linear_terms(obj.func) if a != 0],
            label = string(cr)))
    end
    proof = Dict{Int,Int}()
    derivations = NamedTuple[]
    contradiction = 0
    rounds = 0
    complete = false
    while time()-start < 60
        rounds += 1
        before = length(known)
        for (row, eq) in enumerate(equations)
            unknown = [x for (x, _, _) in eq.terms if !haskey(known,x)]
            length(unknown) <= 1 || continue
            residual = eq.rhs - sum(a*known[x] for (x,a,_) in eq.terms if haskey(known,x); init = Rational{BigInt}(0))
            if isempty(unknown)
                if residual != 0
                    contradiction = row
                    complete = true
                    break
                end
            else
                x = only(unknown)
                a = only(a for (y,a,_) in eq.terms if y == x)
                known[x] = residual/a
                push!(derivations, (variable = x, equation = row))
                proof[x] = length(derivations)
            end
        end
        contradiction > 0 && break
        if length(known) == before
            complete = true
            break
        end
    end
    mkpath(output)
    if contradiction > 0
        used_steps, used_fixed = Set{Int}(), Set{Int}()
        function collect_dependencies(x)
            if haskey(fixed,x)
                push!(used_fixed,x)
                return
            end
            step = proof[x]
            step in used_steps && return
            push!(used_steps,step)
            for (y,_,_) in equations[derivations[step].equation].terms
                y == x || collect_dependencies(y)
            end
        end
        for (x,_,_) in equations[contradiction].terms
            collect_dependencies(x)
        end
        row_dict(row, variable) = Dict("derived_variable" => variable, "model_equation_index" => row,
            "rhs_ieee754" => equations[row].rhs_bits,
            "variables" => [x for (x,_,_) in equations[row].terms],
            "coefficients_ieee754" => [z for (_,_,z) in equations[row].terms])
        certificate = Dict("schema" => "r9-affine-rational-certificate-v1",
            "fixed" => [Dict("variable" => x, "value_ieee754" => fixed_bits[x]) for x in sort(collect(used_fixed))],
            "steps" => [row_dict(derivations[k].equation, derivations[k].variable) for k in sort(collect(used_steps))],
            "contradiction" => row_dict(contradiction, 0),
            "scope" => "exact binary coefficients of frozen original "*mode*" model; not physical impossibility")
        write(joinpath(output,"certificate.toml"), R9PVStudy.textfile(certificate))
    end
    summary = Dict("schema" => "r9-affine-exact-audit-v1", "input_sha256" => f.c.sha256,
        "parent_manifest_sha256" => R9PVStudy.hashfile(joinpath(batch,"manifest.toml")),
        "fixed_variables" => length(fixed), "derived_variables" => length(known)-length(fixed),
        "rounds" => rounds, "completed" => complete, "contradiction_found" => contradiction > 0,
        "elapsed_sec" => time()-start, "mode" => mode, "scope" => "saved binary affine equalities and fixed variables only")
    write(joinpath(output,"audit.toml"), R9PVStudy.textfile(summary))
    cp(@__FILE__, joinpath(output,"audit-source.jl"))
    println(summary)
end
length(ARGS) in (2,3) || error("usage: audit_r9_affine_exact.jl FROZEN_BATCH NEW_OUTPUT [CF_CT|CF_VT]")
audit_affine_exact(ARGS...)
