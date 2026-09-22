# 开发基准：先冻结输入再求解；不是100情景风险或样本外实验。
started=time()
using PaperRebuild, JuMP, Clarabel, TOML, SHA

length(ARGS)==2 && ARGS[1] in ("input", "nominal") ||
    error("usage: probe_r9_reserve.jl input|nominal NEW_DIRECTORY")
root=normpath(joinpath(@__DIR__, ".."))
directory=abspath(ARGS[2])
ispath(directory) && error("Preserve old runs: choose a new directory")
mkpath(directory)
write_toml(path, data) = open(io->TOML.print(io, data; sorted = true), path, "w")
try
    c=r9_reserve_template(
        joinpath(root, "docs/reading/ch07"),
        joinpath(root, "configs/r9/reserve-protocol.toml"),
    )
    audit=audit_r9_reserve_input(c)
    write_toml(joinpath(directory, "template.toml"), c.data)
    write_toml(joinpath(directory, "input-audit.toml"), audit)
    source=Dict{String,String}()
    for rel in (
        "src/core/r9_reserve.jl",
        "src/verification/r9_reserve.jl",
        "scripts/probe_r9_reserve.jl",
        "configs/r9/reserve-protocol.toml",
        "docs/reading/ch07/inputs.toml",
        "docs/reading/ch07/topology.toml",
        "Project.toml",
        "Manifest.toml",
    )
        file=joinpath(root, split(rel, '/')...)
        target=joinpath(directory, "input-code", split(rel, '/')...)
        mkpath(dirname(target))
        cp(file, target)
        source[rel]=bytes2hex(sha256(read(file)))
    end
    write_toml(joinpath(directory, "input-hashes.toml"), source)
    println("reference_pass=", audit["reference_pass"], " input=", c.sha256)
    if ARGS[1]=="nominal"
        T=c.data["T"]
        d=Dict{String,Any}(
            "schema"=>"r5-commitment-case-v1",
            "origin"=>"synthetic",
            "name"=>c.data["name"]*"-nominal-no-reserve",
            "objective"=>"expected_net_cost",
            "recourse_information"=>"complete_trajectory",
            "comfort"=>"hard_each_scenario",
            "uncertain_fields"=>String[],
            "day_ahead"=>Dict(
                k=>copy(c.data["award"][k]) for k in ("energy_price", "up_price", "down_price")
            ),
            "bounds"=>Dict(
                k=>Dict(
                    "lower"=>zeros(T),
                    "upper"=>fill(k=="P_DA_MW" ? c.data["electric"]["pcc_max_MW"] : 0.0, T),
                ) for k in PaperRebuild.R5_COMMITMENT_KEYS
            ),
            "scenarios"=>[Dict("id"=>"nominal", "probability"=>1.0, "case"=>c.data)],
        )
        base=R5CommitmentCase(d)
        write_toml(joinpath(directory, "commitment-input.toml"), base.data)
        budget=600.0-(time()-started)
        budget>0 || error("Budget exhausted before model construction")
        opt=optimizer_with_attributes(
            Clarabel.Optimizer,
            "tol_feas"=>1e-9,
            "tol_gap_abs"=>1e-9,
            "tol_gap_rel"=>1e-9,
        )
        result=solve_r5_commitment(base; optimizer = opt, budget_sec = budget)
        path=save_r5_commitment_run(base, result, joinpath(directory, "run"))
        saved=read_r5_commitment_run(path)
        write_toml(
            joinpath(directory, "probe-status.toml"),
            Dict(
                "schema"=>"r9-reserve-probe-v1",
                "formal_risk_experiment"=>false,
                "elapsed_sec"=>time()-started,
                "complete_process_budget_sec"=>600.0,
                "budget_pass"=>time()-started<=600.0,
                "case_sha256"=>base.sha256,
                "status"=>result["status"],
                "model_pass"=>saved.validation["model_pass"],
                "kkt_pass"=>saved.validation["kkt_pass"],
                "cost_optimization_complete"=>result["cost_optimization_complete"],
            ),
        )
        println(
            "status=",
            result["status"],
            " model=",
            saved.validation["model_pass"],
            " kkt=",
            saved.validation["kkt_pass"],
            " cost=",
            get(result, "solver_objective", "missing"),
        )
    end
    all(
        bytes2hex(sha256(read(joinpath(root, split(rel, '/')...))))==hash for (rel, hash) in source
    ) || error("Input/probe source changed during run")
catch err
    open(joinpath(directory, "failure.txt"), "w") do io
        showerror(io, err, catch_backtrace())
        println(io)
    end
    rethrow()
end
