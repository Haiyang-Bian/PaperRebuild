# 第一条语句即开始预算；使用冻结源码求解，不把导入/JIT遗漏在预算之外。
const R9_TRADING_PROCESS_START=time_ns()/1e9
module R9TradingStudy
using TOML, SHA, Dates, Pkg
const ROOT=normpath(joinpath(@__DIR__, ".."))
ROOT in LOAD_PATH || push!(LOAD_PATH, ROOT)
let depot=joinpath(ROOT, ".julia")
    isdir(depot) && !(depot in DEPOT_PATH) && pushfirst!(DEPOT_PATH, depot)
end
clock() = time_ns()/1e9
hashfile(p) = bytes2hex(sha256(read(p)))
toml(p, x) = open(io->TOML.print(io, x; sorted = true), p, "w")
safeid(s) = occursin(r"^[a-z][a-z0-9-]*$", s) || error("Invalid method id")
function safe(root, relative)
    isabspath(relative) || occursin(':', relative) || occursin('\\', relative) ?
    error("Invalid relative path") : nothing
    all(x->!isempty(x) && x ∉ (".", ".."), split(relative, '/')) || error("Invalid relative path")
    p=abspath(root)
    for part in split(relative, '/')
        p=joinpath(p, part)
        islink(p) && error("Symlink not allowed in frozen study")
    end
    p
end
function library(root)
    wrapper=Module(gensym(:R9TradingStudyFrozen))
    Base.include(wrapper, joinpath(root, "src", "PaperRebuild.jl"))
    Base.invokelatest(getfield, wrapper, :PaperRebuild)
end
function call(lib, name, args...; kwargs...)
    f=Base.invokelatest(getfield, lib, name)
    Base.invokelatest(f, args...; kwargs...)
end

"""核对四方法的预先声明边界；不推断作者未公开设置，也不按结果调整参数。"""
function validate_protocol(p)
    p["schema"]=="r9-trading-study-protocol-v1" && p["origin"]=="synthetic" ||
        error("Study protocol identity")
    p["budget_sec"]==600 && p["local_budget_sec"]==60 && p["validation_reserve_fraction"]==0.1 ||
        error("Study budget changed")
    expected=Set((op, el) for op in ("independent", "central") for el in ("socp", "exact"))
    Set((x["operation"], x["electric"]) for x in p["methods"])==expected ||
        error("Four-method coverage missing")
    length(p["methods"])==4 && allunique(x["id"] for x in p["methods"]) || error("Repeated methods")
    foreach(x->safeid(x["id"]), p["methods"])
    p["integer_rule"]=="all_storage_and_heat_direction_choices_free" ||
        error("Integer domain changed")
    p["gurobi"]==Dict(
        "Threads"=>1,
        "Seed"=>0,
        "NonConvex"=>2,
        "MIPGap"=>1e-4,
        "FeasibilityTol"=>1e-8,
        "OptimalityTol"=>1e-8,
        "IntFeasTol"=>1e-8,
    ) || error("Solver protocol changed")
    true
end

"""从既有输入协议冻结案例、全部科学源码和执行脚本；不得覆盖既有批次。"""
function freeze(out; root = ROOT)
    ispath(out) && error("Do not overwrite study")
    protocol_path=joinpath(root, "configs/r9/trading-study.toml")
    p=TOML.parsefile(protocol_path)
    validate_protocol(p)
    lib=library(root)
    c=call(
        lib,
        :r9_trading_case,
        joinpath(root, "docs/reading/ch07"),
        joinpath(root, p["input_protocol"]),
    )
    c.sha256==p["expected_input_sha256"] || error("Previously frozen input changed")
    hashes=call(lib, :r9_trading_science_hashes)
    for rel in (
        "scripts/r9_trading_study.jl",
        "configs/r9/trading-study.toml",
        p["input_protocol"],
        "docs/reading/ch07/inputs.toml",
        "docs/reading/ch07/topology.toml",
        "docs/reading/ch07/reported-results.toml",
        "docs/reading/ch07/trading.toml",
    )
        hashes[rel]=hashfile(joinpath(root, rel))
    end
    mkpath(out)
    files=Dict{String,String}()
    for (rel, h) in hashes
        source=safe(root, rel)
        hashfile(source)==h || error("Source changed while freezing")
        target=safe(out, "code/"*rel)
        mkpath(dirname(target))
        cp(source, target)
        files["code/"*rel]=h
    end
    write(joinpath(out, "input.toml"), c.source_text)
    files["input.toml"]=hashfile(joinpath(out, "input.toml"))
    githead=readchomp(`git -C $root rev-parse HEAD`)
    gitbranch=readchomp(`git -C $root branch --show-current`)
    status=read(`git -C $root status --porcelain=v1`, String)
    # 只记录相对文件状态，不含远程URL、账户或机器绝对路径。
    meta=Dict(
        "schema"=>"r9-trading-study-v1",
        "origin"=>"synthetic",
        "files"=>files,
        "protocol"=>p,
        "input_sha256"=>c.sha256,
        "git_commit"=>githead,
        "git_branch"=>gitbranch,
        "git_status"=>status,
        "created_utc"=>string(now(UTC)),
        "julia_version"=>string(VERSION),
        "source_hashes"=>hashes,
        "optimization_performed_at_freeze"=>false,
    )
    toml(joinpath(out, "manifest.toml"), meta)
    println("Frozen four methods, no optimization: ", c.sha256)
    meta
end

function check_inputs(out)
    meta=TOML.parsefile(joinpath(out, "manifest.toml"))
    meta["schema"]=="r9-trading-study-v1" && meta["origin"]=="synthetic" ||
        error("Study identity changed")
    validate_protocol(meta["protocol"])
    !meta["optimization_performed_at_freeze"] || error("Freeze receipt changed")
    actual=Set{String}()
    for (dir, dirs, names) in walkdir(joinpath(out, "code"))
        any(x->islink(joinpath(dir, x)), [dirs; names]) && error("Frozen source symlink")
        for name in names
            push!(actual, replace(relpath(joinpath(dir, name), out), '\\'=>'/'))
        end
    end
    actual==Set(p for p in keys(meta["files"]) if startswith(p, "code/")) ||
        error("Frozen source inventory changed")
    for (rel, h) in meta["files"]
        hashfile(safe(out, rel))==h || error("Frozen study file changed: $rel")
    end
    meta["input_sha256"] ==
    meta["protocol"]["expected_input_sha256"] ==
    meta["files"]["input.toml"] || error("Study input identity mismatch")
    TOML.parsefile(safe(out, "code/configs/r9/trading-study.toml"))==meta["protocol"] ||
        error("Protocol carrier changed")
    Set(keys(meta["files"]))==union(
        Set("code/"*p for p in keys(meta["source_hashes"])),
        Set(["input.toml"]),
    ) || error("Missing source coverage")
    all(meta["files"]["code/"*p]==h for (p, h) in meta["source_hashes"]) ||
        error("Source hash declarations disagree")
    meta
end

"""单方法完整600秒；求解器环境延迟到工厂内部建立，使许可失败进入阶段证据。"""
function execute(out, id; process_start = clock())
    VERSION==v"1.12.6" || error("Expected Julia 1.12.6")
    meta=check_inputs(out)
    safeid(id)
    entry=only(x for x in meta["protocol"]["methods"] if x["id"]==id)
    hashfile(@__FILE__)==meta["files"]["code/scripts/r9_trading_study.jl"] ||
        error("Run the frozen version of the study script")
    target=joinpath(out, "runs", id)
    ispath(target) && error("Do not overwrite method evidence")
    mkpath(target)
    receipt=Dict{String,Any}(
        "schema"=>"r9-trading-method-receipt-v1",
        "entry"=>entry,
        "input_sha256"=>meta["input_sha256"],
        "origin"=>"synthetic",
        "manifest_sha256"=>hashfile(joinpath(out, "manifest.toml")),
        "julia_version"=>string(VERSION),
        "start_utc"=>string(now(UTC)),
        "budget_sec"=>meta["protocol"]["budget_sec"],
        "solver_options"=>meta["protocol"]["gurobi"],
        "initial_primal_injection"=>false,
        "uses_projected_gradient"=>false,
        "distributed_algorithm"=>false,
        "bargaining"=>false,
        "validation_source"=>"frozen_source",
        "command"=>"r9_trading_study.jl run STUDY "*id,
    )
    try
        lib=library(joinpath(out, "code"))
        c=call(lib, :load_r9_trading_case, joinpath(out, "input.toml"))
        Core.eval(@__MODULE__, :(using Gurobi, JuMP))
        receipt["runtime_packages"]=Dict(
            info.name=>Dict("uuid"=>string(id), "version"=>string(info.version)) for
            (id, info) in Pkg.dependencies() if
            info.name in ("Gurobi", "Gurobi_jll", "JuMP", "MathOptInterface", "CSV", "TOML")
        )
        factory=Base.invokelatest() do
            environment=Ref{Any}(nothing)
            creator=()->begin
                environment[]===nothing &&
                    (environment[]=Gurobi.Env(Dict{String,Any}("OutputFlag"=>0)))
                Gurobi.Optimizer(environment[])
            end
            JuMP.optimizer_with_attributes(creator, collect(meta["protocol"]["gurobi"])...)
        end
        result=call(
            lib,
            :solve_r9_trading_case,
            c;
            optimizer = factory,
            operation = Symbol(entry["operation"]),
            electric = Symbol(entry["electric"]),
            budget_sec = meta["protocol"]["budget_sec"],
            deadline = process_start+meta["protocol"]["budget_sec"],
        )
        receipt["method_elapsed_sec"]=clock()-process_start
        receipt["method_budget_pass"]=receipt["method_elapsed_sec"]<=meta["protocol"]["budget_sec"]
        # 保存前先保留原值；即使封存检查失败，原始阶段仍可追溯。
        toml(joinpath(target, "raw-result.toml"), result)
        path=call(lib, :save_r9_trading_run, c, result; directory = target, run_id = "record")
        receipt["record"]="record"
        receipt["status"]=result["status"]
        receipt["run_validation"]=result["validation"]
        receipt["record_manifest_sha256"]=hashfile(joinpath(path, "hashes.toml"))
        receipt["raw_result_sha256"]=hashfile(joinpath(target, "raw-result.toml"))
        println(
            id,
            ": ",
            result["status"],
            "; model=",
            result["validation"]["model_pass"],
            "; original=",
            result["validation"]["electric_original_pass"],
            "; cost=",
            get(result, "system_cost_CNY", "unavailable"),
        )
    catch err
        err isa InterruptException && rethrow()
        receipt["status"]="startup_or_archive_error"
        receipt["error_type"]=string(typeof(err))
        # 完整本机堆栈留在外层忽略日志；不把路径、账户或许可证信息写入公开收据。
        receipt["error_category"]=occursin(r"(?i)license|licence", sprint(showerror, err)) ?
                                  "license_initialization" : "execution_or_archive"
        println(stderr, "Method stopped: ", id, "; ", receipt["error_type"])
        showerror(stderr, err, catch_backtrace())
        println(stderr)
    end
    receipt["process_elapsed_with_archive_sec"]=clock()-process_start
    receipt["process_budget_pass"]=receipt["process_elapsed_with_archive_sec"]<=receipt["budget_sec"]
    haskey(receipt, "method_elapsed_sec") ||
        (receipt["method_elapsed_sec"]=receipt["process_elapsed_with_archive_sec"])
    receipt["method_budget_pass"]=receipt["method_elapsed_sec"]<=receipt["budget_sec"]
    toml(joinpath(target, "receipt.toml"), receipt)
    haskey(receipt, "record") || error("Method evidence incomplete; original files preserved")
    receipt
end

function main(args)
    length(args)==2 && args[1]=="freeze" && return freeze(abspath(args[2]))
    length(args)==2 && args[1]=="check-inputs" && return check_inputs(abspath(args[2]))
    length(args)==3 &&
        args[1]=="run" &&
        return execute(
            abspath(args[2]),
            args[3];
            process_start = getfield(parentmodule(@__MODULE__), :R9_TRADING_PROCESS_START),
        )
    error("usage: r9_trading_study.jl freeze NEW_STUDY | check-inputs STUDY | run STUDY METHOD")
end
end
if abspath(PROGRAM_FILE)==abspath(@__FILE__)
    R9TradingStudy.main(ARGS)
end
