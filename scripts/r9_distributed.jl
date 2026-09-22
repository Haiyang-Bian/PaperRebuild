# 显式命令入口；保存完整迭代，不自动挑模式、换数据或注入参考解。
using PaperRebuild, JuMP, TOML, SHA, Dates, Pkg

function r9_distributed_cli(args)
    VERSION==v"1.12.6" || error("Expected Julia 1.12.6")
    if length(args)==2 && args[1]=="check"
        r=read_r9_distributed_run(args[2])
        TOML.print(stdout, r.validation; sorted = true)
        return
    end
    length(args)==5 && args[1]=="run" || error(
        "usage: r9_distributed.jl run INPUT.toml RULES.toml DIRECTORY RUN_ID | check RUN_DIRECTORY",
    )
    c=load_r9_trading_case(args[2])
    rule_text=read(args[3], String)
    rules=TOML.parse(rule_text)
    rules["schema"]=="r9-distributed-rules-v1" || error("Unknown rules schema")
    spec=R9DistributedSpec(;
        algorithm = Symbol(rules["algorithm"]),
        rho = rules["rho"],
        max_iterations = rules["max_iterations"],
    )
    modes=haskey(rules, "fixed_modes") ?
          Dict(k=>PaperRebuild.r4_matrix(v) for (k, v) in rules["fixed_modes"]) : nothing
    options=get(rules, "solver_options", Dict{String,Any}())
    if rules["solver"]=="Clarabel"
        @eval using Clarabel
        factory=Base.invokelatest() do
            optimizer_with_attributes(Clarabel.Optimizer, collect(options)...)
        end
    elseif rules["solver"]=="Gurobi"
        # Gurobi由tools/solvers提供；缺许可时保留失败，不暗换开放求解器。
        @eval using Gurobi
        factory=Base.invokelatest() do
            environment=Ref{Any}(nothing)
            creator=()->begin
                environment[]===nothing &&
                    (environment[]=Gurobi.Env(Dict{String,Any}("OutputFlag"=>0)))
                Gurobi.Optimizer(environment[])
            end
            optimizer_with_attributes(creator, collect(options)...)
        end
    else
        error("Solver must be Clarabel or Gurobi")
    end
    started=string(now(UTC))
    r=Base.invokelatest(
        solve_r9_distributed,
        c;
        optimizer = factory,
        modes,
        spec,
        budget_sec = rules["budget_sec"],
        objective_record = Symbol(get(rules, "objective_record", "reported")),
    )
    r["execution"]=Dict(
        "rules_text"=>rule_text,
        "rules_sha256"=>bytes2hex(sha256(rule_text)),
        "julia_version"=>string(VERSION),
        "started_utc"=>started,
        "packages"=>Dict(
            info.name=>string(info.version) for (_, info) in Pkg.dependencies() if
            info.name in ("JuMP", "MathOptInterface", "Clarabel", "Gurobi", "Gurobi_jll")
        ),
    )
    path=save_r9_distributed_run(c, r; directory = args[4], run_id = args[5])
    println("saved=", path)
    println("status=", r["status"], " iterations=", length(r["trace"]))
    TOML.print(stdout, r["validation"]; sorted = true)
end

r9_distributed_cli(ARGS)
