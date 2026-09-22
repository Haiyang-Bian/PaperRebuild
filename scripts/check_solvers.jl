# Analytically soluble capability checks, not thesis models or performance benchmarks.
using JuMP
import Gurobi
using Dates
using SHA
using TOML

function check_solvers()
    VERSION == v"1.12.6" || error("Use Julia 1.12.6.")
    root = normpath(joinpath(@__DIR__, ".."))
    parent = joinpath(root, "tmp", "solver-checks")
    mkpath(parent)
    output = mktempdir(parent; prefix = "qualification-", cleanup = false)
    results = Dict{String,Any}[]
    report = Dict{String,Any}(
        "schema_version" => 1,
        "scope" => "solver_capability_only_not_thesis_reproduction",
        "started_utc" => string(now(UTC)),
        "julia_version" => string(VERSION),
        "jump_version" => string(pkgversion(JuMP)),
        "gurobi_jl_version" => string(pkgversion(Gurobi)),
        "script_sha256" => bytes2hex(sha256(read(@__FILE__))),
        "manifest_sha256" =>
            bytes2hex(sha256(read(joinpath(root, "tools", "solvers", "Manifest.toml")))),
        "checks" => results,
    )
    environment = nothing
    try
        # Do not emit or record license IDs, credential parameters, or license paths.
        environment = Gurobi.Env(Dict{String,Any}("OutputFlag" => 0))
        model_factory() = Model(() -> Gurobi.Optimizer(environment))
        report["solver_version"] = MOI.get(backend(model_factory()), MOI.SolverVersion())

        function check_case(name, build_and_check)
            entry = Dict{String,Any}("name" => name, "passed" => false)
            push!(results, entry)
            try
                model = model_factory()
                set_silent(model)
                set_time_limit_sec(model, 30.0)
                set_attribute(model, "Threads", 1)
                set_attribute(model, "Seed", 0)
                build_and_check(model, entry)
                entry["passed"] = true
            catch err
                # Keep the report portable and avoid copying solver license diagnostics.
                entry["error_type"] = string(typeof(err))
            end
            println(name, ": ", entry["passed"] ? "PASS" : "FAIL")
        end

        function solved(model, entry, expected)
            optimize!(model)
            entry["termination"] = string(termination_status(model))
            entry["primal_status"] = string(primal_status(model))
            entry["dual_status"] = string(dual_status(model))
            @assert termination_status(model) == MOI.OPTIMAL
            @assert primal_status(model) == MOI.FEASIBLE_POINT
            entry["objective"] = objective_value(model)
            entry["objective_bound"] = objective_bound(model)
            @assert isapprox(entry["objective"], expected; atol = 1e-6, rtol = 1e-6)
            @assert isapprox(entry["objective_bound"], expected; atol = 1e-5, rtol = 1e-5)
        end

        check_case("LP and dual", function (model, entry)
            @variable(model, x >= 0)
            @variable(model, y >= 0)
            balance = @constraint(model, x + y >= 1)
            @objective(model, Min, 2x + 3y)
            solved(model, entry, 2.0)
            @assert dual_status(model) == MOI.FEASIBLE_POINT
            entry["balance_dual"] = dual(balance)
            @assert isapprox(dual(balance), 2.0; atol = 1e-6)
        end)

        check_case("MILP", function (model, entry)
            @variable(model, x, Bin)
            @constraint(model, x >= 0.3)
            @objective(model, Min, x)
            solved(model, entry, 1.0)
        end)

        check_case(
            "SOCP and continuous dual",
            function (model, entry)
                set_attribute(model, "QCPDual", 1)
                @variable(model, t >= 0)
                @variable(model, x)
                fixed = @constraint(model, x == 3)
                @constraint(model, [t, x, 4.0] in SecondOrderCone())
                @objective(model, Min, t)
                solved(model, entry, 5.0)
                @assert dual_status(model) == MOI.FEASIBLE_POINT
                entry["fixed_dual"] = dual(fixed)
                @assert isapprox(dual(fixed), 0.6; atol = 1e-4)
            end,
        )

        check_case("MISOCP", function (model, entry)
            @variable(model, t >= 0)
            @variable(model, x, Bin)
            @constraint(model, x >= 0.3)
            @constraint(model, [t, 3x, 4.0] in SecondOrderCone())
            @objective(model, Min, t)
            solved(model, entry, 5.0)
        end)

        check_case("bounded nonconvex quadratic", function (model, entry)
            set_attribute(model, "NonConvex", 2)
            set_attribute(model, "MIPGap", 1e-6)
            @variable(model, 0 <= x <= 2)
            @variable(model, 0 <= y <= 2)
            @constraint(model, x + y <= 2)
            @objective(model, Max, x * y)
            solved(model, entry, 1.0)
            @assert abs(value(x) + value(y) - 2) <= 1e-5
        end)

        check_case("nonlinear expression interface", function (model, entry)
            @variable(model, 0 <= x <= 1)
            @variable(model, 0 <= z <= 4)
            @constraint(model, z >= exp(x))
            @objective(model, Min, z)
            solved(model, entry, 1.0)
        end)

        check_case(
            "infeasible status without solution access",
            function (model, entry)
                set_attribute(model, "DualReductions", 0)
                @variable(model, x)
                @constraint(model, x >= 1)
                @constraint(model, x <= 0)
                @objective(model, Min, x)
                optimize!(model)
                entry["termination"] = string(termination_status(model))
                @assert termination_status(model) == MOI.INFEASIBLE
                @assert !has_values(model)
            end,
        )

        check_case("license size check: 2101 variables", function (model, entry)
            @variable(model, x[1:2101] >= 0)
            @constraint(model, sum(x) >= 1)
            @objective(model, Min, sum(x))
            solved(model, entry, 1.0)
        end)
    catch err
        report["initialization_error_type"] = string(typeof(err))
    finally
        report["completed_utc"] = string(now(UTC))
        report["passed"] = length(results) == 8 && all(r["passed"] for r in results)
        open(joinpath(output, "report.toml"), "w") do io
            TOML.print(io, report; sorted = true)
        end
        println("Report: ", relpath(joinpath(output, "report.toml"), root))
    end
    report["passed"] || error("Solver qualification failed; inspect the local TOML report.")
    println("All capability checks passed; thesis models remain unimplemented.")
end

if abspath(PROGRAM_FILE) == @__FILE__
    check_solvers()
end
