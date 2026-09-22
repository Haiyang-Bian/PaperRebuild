const R9_NETWORK_PROCESS_START=time_ns()/1e9
module R9NetworkStudy
include("r9_trading_study.jl")
using .R9TradingStudy: safe, library, call, toml, hashfile, clock
using TOML, SHA, Dates, Pkg
const ROOT=normpath(joinpath(@__DIR__, ".."))

function protocol(root)
    p=TOML.parsefile(joinpath(root, "configs/r9/network-study.toml"))
    p["schema"]=="r9-network-study-protocol-v1" && p["origin"]=="synthetic" ||
        error("Study identity")
    p["designs"]==["legacy", "equipment"] &&
    p["policies"]==["fixed", "joint"] &&
    p["operations"]==["independent", "central"] &&
    p["electric_versions"]==["socp", "exact"] || error("Frozen 2x2x2x2 domain")
    p["budget_sec"]==600 &&
    !p["author_equivalence"] &&
    !p["uses_projected_gradient"] &&
    !p["distributed_algorithm"] &&
    !p["bargaining"] || error("Scientific scope changed")
    p
end

"""冻结四份输入与十六方法；原失败输入作为父对象，不允许按收益选择参数。"""
function freeze(out; root = ROOT)
    ispath(out) && error("Do not overwrite study")
    p=protocol(root)
    lib=library(root)
    parent=call(
        lib,
        :r9_trading_case,
        joinpath(root, "docs/reading/ch07"),
        joinpath(root, p["input_protocol"]),
    )
    parent.sha256==p["expected_parent_sha256"] || error("Parent changed")
    cases=Dict{String,Any}()
    methods=Dict{String,Any}[]
    for design in p["designs"], policy in p["policies"]
        id=design*"-"*policy
        c=call(
            lib,
            :r9_reconfiguration_case,
            parent,
            joinpath(root, p["network_protocol"]);
            design = Symbol(design),
            policy = Symbol(policy),
        )
        cases[id]=c
        for op in p["operations"], el in p["electric_versions"]
            push!(
                methods,
                Dict(
                    "id"=>id*"-"*op*"-"*el,
                    "case"=>id,
                    "design"=>design,
                    "policy"=>policy,
                    "operation"=>op,
                    "electric"=>el,
                    "input_sha256"=>c.sha256,
                ),
            )
        end
    end
    hashes=call(lib, :r9_trading_science_hashes)
    for rel in (
        "scripts/r9_network_study.jl",
        "scripts/r9_trading_study.jl",
        "scripts/run_r9_network_batch.jl",
        "configs/r9/network-study.toml",
        p["input_protocol"],
        p["network_protocol"],
        "docs/reading/ch07/inputs.toml",
        "docs/reading/ch07/topology.toml",
        "docs/reading/ch07/reported-results.toml",
    )
        hashes[rel]=hashfile(joinpath(root, rel))
    end
    mkpath(out)
    files=Dict{String,String}()
    for (rel, h) in hashes
        source=safe(root, rel)
        hashfile(source)==h || error("Concurrent source change")
        target=safe(out, "code/"*rel)
        mkpath(dirname(target))
        cp(source, target)
        files["code/"*rel]=h
    end
    for (id, c) in cases
        rel="inputs/"*id*".toml"
        path=safe(out, rel)
        mkpath(dirname(path))
        write(path, c.source_text)
        files[rel]=hashfile(path)
    end
    write(joinpath(out, "parent.toml"), parent.source_text)
    files["parent.toml"]=parent.sha256
    meta=Dict(
        "schema"=>"r9-network-study-v1",
        "files"=>files,
        "source_hashes"=>hashes,
        "protocol"=>p,
        "methods"=>methods,
        "origin"=>"synthetic",
        "julia_version"=>string(VERSION),
        "git_commit"=>readchomp(`git -C $root rev-parse HEAD`),
        "git_branch"=>readchomp(`git -C $root branch --show-current`),
        "git_status"=>read(`git -C $root status --porcelain=v1`, String),
        "created_utc"=>string(now(UTC)),
        "optimization_performed_at_freeze"=>false,
    )
    toml(joinpath(out, "manifest.toml"), meta)
    println("Frozen ", length(cases), " inputs and ", length(methods), " methods; no optimization")
    meta
end

"""哈希和配对条件检查；只读，不加载商业许可。"""
function check(out)
    m=TOML.parsefile(joinpath(out, "manifest.toml"))
    m["schema"]=="r9-network-study-v1" && !m["optimization_performed_at_freeze"] ||
        error("Freeze identity changed")
    for (rel, h) in m["files"]
        hashfile(safe(out, rel))==h || error("Frozen bytes changed: $rel")
    end
    protocol(joinpath(out, "code"))==m["protocol"] || error("Protocol changed")
    m["files"]["parent.toml"]==m["protocol"]["expected_parent_sha256"] || error("Parent hash")
    length(m["methods"])==16 && allunique(x["id"] for x in m["methods"]) || error("Run matrix")
    expected=Set(
        (a, b, c, d) for a in m["protocol"]["designs"] for b in m["protocol"]["policies"] for
        c in m["protocol"]["operations"] for d in m["protocol"]["electric_versions"]
    )
    Set((x["design"], x["policy"], x["operation"], x["electric"]) for x in m["methods"])==expected ||
        error("Missing factorial group")
    parent=TOML.parsefile(safe(out, "parent.toml"))
    for x in m["methods"]
        id=x["design"]*"-"*x["policy"]
        id==x["case"] && x["id"]==id*"-"*x["operation"]*"-"*x["electric"] || error("Method ID")
        rel="inputs/"*id*".toml"
        m["files"][rel]==x["input_sha256"] || error("Case identity")
        d=TOML.parsefile(safe(out, rel))
        for key in ("actors", "devices", "grid_price", "settlement", "T", "dt_h", "units")
            d[key]==parent[key] || error("Core input changed: $key")
        end
        d["network_control"]["policy"]==x["policy"] &&
        d["network_control"]["design"]==x["design"] || error("Control identity")
        for side in ("electric", "heat")
            other=TOML.parsefile(
                safe(
                    out,
                    "inputs/" *
                    x["design"] *
                    "-" *
                    (x["policy"]=="fixed" ? "joint" : "fixed") *
                    ".toml",
                ),
            )
            d[side]==other[side] || error("Topology contrast also changed parameters")
        end
    end
    m
end

"""单方法含导入/建模/封存共享600秒。运行冻结源码，记录负结果，不调用参考解。"""
function run(out, id; process_start = clock())
    VERSION==v"1.12.6" || error("Julia version")
    m=check(out)
    entry=only(x for x in m["methods"] if x["id"]==id)
    hashfile(@__FILE__)==m["files"]["code/scripts/r9_network_study.jl"] ||
        error("Use the frozen script")
    target=safe(out, "runs/"*id)
    ispath(target) && error("Do not overwrite method")
    mkpath(target)
    p=m["protocol"]
    receipt=Dict{String,Any}(
        "schema"=>"r9-network-receipt-v1",
        "entry"=>entry,
        "manifest_sha256"=>hashfile(joinpath(out, "manifest.toml")),
        "start_utc"=>string(now(UTC)),
        "budget_sec"=>p["budget_sec"],
        "solver_options"=>p["gurobi"],
        "initial_primal_injection"=>false,
        "origin"=>"synthetic",
        "uses_projected_gradient"=>false,
        "distributed_algorithm"=>false,
        "bargaining"=>false,
    )
    try
        lib=library(joinpath(out, "code"))
        c=call(lib, :load_r9_trading_case, safe(out, "inputs/"*entry["case"]*".toml"))
        Core.eval(@__MODULE__, :(using JuMP, Gurobi))
        factory=Base.invokelatest() do
            env=Ref{Any}(nothing)
            maker=()->begin
                env[]===nothing && (env[]=Gurobi.Env(Dict{String,Any}("OutputFlag"=>0)))
                Gurobi.Optimizer(env[])
            end
            JuMP.optimizer_with_attributes(maker, collect(p["gurobi"])...)
        end
        r=call(
            lib,
            :solve_r9_trading_case,
            c;
            optimizer = factory,
            operation = Symbol(entry["operation"]),
            electric = Symbol(entry["electric"]),
            budget_sec = p["budget_sec"],
            deadline = process_start+p["budget_sec"],
        )
        receipt["method_elapsed_sec"]=clock()-process_start
        receipt["method_budget_pass"]=receipt["method_elapsed_sec"]<=p["budget_sec"]
        toml(joinpath(target, "raw-result.toml"), r)
        saved=call(lib, :save_r9_trading_run, c, r; directory = target, run_id = "record")
        receipt["record"]="record"
        receipt["status"]=r["status"]
        receipt["record_manifest_sha256"]=hashfile(joinpath(saved, "hashes.toml"))
        receipt["raw_result_sha256"]=hashfile(joinpath(target, "raw-result.toml"))
        println(
            id,
            ": ",
            r["status"],
            "; model=",
            r["validation"]["model_pass"],
            "; original=",
            r["validation"]["electric_original_pass"],
            "; cost=",
            get(r, "system_cost_CNY", "unavailable"),
        )
    catch err
        err isa InterruptException && rethrow()
        receipt["status"]="startup_or_archive_error"
        receipt["error_type"]=string(typeof(err))
        showerror(stderr, err, catch_backtrace())
        println(stderr)
    end
    receipt["process_elapsed_sec"]=clock()-process_start
    receipt["process_budget_pass"]=receipt["process_elapsed_sec"]<=p["budget_sec"]
    toml(joinpath(target, "receipt.toml"), receipt)
    haskey(receipt, "record") || error("Incomplete method, original evidence preserved")
    receipt
end

function main(args)
    length(args)==2 && args[1]=="freeze" && return freeze(abspath(args[2]))
    length(args)==2 && args[1]=="check" && return check(abspath(args[2]))
    length(args)==3 &&
        args[1]=="run" &&
        return run(
            abspath(args[2]),
            args[3];
            process_start = getfield(parentmodule(@__MODULE__), :R9_NETWORK_PROCESS_START),
        )
    error("usage: r9_network_study.jl freeze NEW_STUDY | check STUDY | run STUDY METHOD")
end
end
abspath(PROGRAM_FILE)==abspath(@__FILE__) && R9NetworkStudy.main(ARGS)
