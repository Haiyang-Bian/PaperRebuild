# 完整方法时钟包含装载；冻结源码运行，集中参考不进入分布初值。
const R9_DISTRIBUTED_STUDY_START=time_ns()/1e9
module R9DistributedStudy
include("r9_trading_study.jl")
using .R9TradingStudy: safe, library, call, toml, hashfile, clock
using TOML, Dates, Pkg
const ROOT=normpath(joinpath(@__DIR__, ".."))
const PROTOCOL="configs/r9/distributed-corridor-study.toml"

"""只读取输入与预先声明规则；v1仅重读错误历史，v2纠正关闭管，v3反向EB3至节点3的走廊。"""
function input_modes(c; version = 2)
    version in (1, 2, 3) || error("Unknown mode rule version")
    d=c.data
    T=d["T"]
    z=zeros(Int, length(d["devices"]), T)
    midpoint=(minimum(d["grid_price"])+maximum(d["grid_price"]))/2
    for (j, g) in enumerate(d["devices"]), t in 1:T
        g["kind"] in ("BS", "HS") && (z[j, t]=Int(d["grid_price"][t]<=midpoint))
    end
    n=d["network_control"]
    modes=Dict(
        "z_storage"=>z,
        "heat_direction"=>version==1 ? ones(Int, length(d["heat"]["pipes"]), T) :
                          repeat(reshape(n["heat_initial"], :, 1), 1, T),
        "u_E"=>repeat(reshape(n["electric_initial"], :, 1), 1, T),
        "u_H"=>reshape(n["heat_initial"], :, 1),
    )
    if version==3
        for pair in ((3, 25), (25, 24), (24, 5))
            j=only(findall(p->(p["from"], p["to"])==pair, d["heat"]["pipes"]))
            n["heat_initial"][j]==1 || error("Declared source corridor is closed")
            modes["heat_direction"][j, :].=0
        end
    end
    modes
end

function protocol(root, path = PROTOCOL)
    p=TOML.parsefile(safe(root, path))
    p["schema"] in (
        "r9-distributed-study-protocol-v1",
        "r9-distributed-study-protocol-v2",
        "r9-distributed-study-protocol-v3",
    ) && p["origin"]=="synthetic" || error("Study identity")
    p["budget_sec"]==600 &&
    p["archive_reserve_sec"]==60 &&
    p["rho"]==1 &&
    p["max_iterations"]==1000 || error("Frozen numerical rules changed")
    !p["central_solution_injected"] && !p["author_code_equivalence"] || error("Claim boundary")
    p["initialization"]=="zero_messages_and_scaled_duals" || error("Initialization changed")
    corrected=p["schema"]=="r9-distributed-study-protocol-v2"
    corridor=p["schema"]=="r9-distributed-study-protocol-v3"
    mode_rule=corridor ?
              "initial_topology; reverse_3_25_24_5_heat_corridor; storage_charge_at_or_below_price_midrange" :
              corrected ?
              "initial_topology; open_heat_positive_closed_heat_zero; storage_charge_at_or_below_price_midrange" :
              "initial_topology; reference_positive_heat_direction; storage_charge_at_or_below_price_midrange"
    p["fixed_mode_rule"]==mode_rule || error("Mode rule changed")
    if corridor
        p["reverse_heat_corridor"]==[[3, 25], [25, 24], [24, 5]] &&
        p["objective_record"]=="separate" || error("Declared diagnostic revision changed")
        !p["original_preregistered_design"] ||
            error("Post-diagnostic revision disguised as original protocol")
    end
    expected=Set(
        (c, d, m, s) for (c, d, s) in (
            ("equipment-fixed", "fixed_modes", "Clarabel"),
            ("equipment-fixed", "mixed_integer", "Gurobi"),
            ("equipment-joint", "mixed_integer", "Gurobi"),
        ) for m in ("central", "admm")
    )
    corrected && (expected=filter(x->x[2]=="fixed_modes", expected))
    length(p["methods"])==length(expected) && allunique(x["id"] for x in p["methods"]) ||
        error("Frozen method count differs")
    Set((x["case"], x["domain"], x["method"], x["solver"]) for x in p["methods"])==expected ||
        error("Paired method coverage")
    p
end

"""从已封存网络批次复制原输入，先冻结声明的方法、模式和科学源码，再允许求解。"""
function freeze(parent, out; root = ROOT, protocol_path = PROTOCOL)
    ispath(out) && error("Do not overwrite study")
    p=protocol(root, protocol_path)
    p["schema"] in ("r9-distributed-study-protocol-v2", "r9-distributed-study-protocol-v3") ||
        error("Historical v1 contains contradictory closed-pipe modes; use an explicit revision")
    hashfile(safe(parent, "manifest.toml"))==p["parent_manifest_sha256"] ||
        error("Parent manifest changed")
    lib=library(root)
    cases=Dict{String,Any}()
    for policy in ("fixed", "joint")
        id="equipment-"*policy
        path=safe(parent, "inputs/"*id*".toml")
        hashfile(path)==p[policy*"_input_sha256"] || error("Frozen parent input changed")
        c=call(lib, :load_r9_trading_case, path)
        c.data["T"]==24 && length(c.data["actors"])==9 && c.data["origin"]=="synthetic" ||
            error("Scale input identity")
        c.data["network_control"]["policy"]==policy || error("Topology policy mismatch")
        cases[id]=c
    end
    for key in ("T", "dt_h", "actors", "devices", "grid_price", "settlement", "electric", "heat")
        cases["equipment-fixed"].data[key]==cases["equipment-joint"].data[key] ||
            error("Paired core differs")
    end
    hashes=call(lib, :r9_trading_science_hashes)
    for rel in (protocol_path, "scripts/r9_distributed_study.jl", "scripts/r9_trading_study.jl")
        hashes[rel]=hashfile(safe(root, rel))
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
        target=safe(out, rel)
        mkpath(dirname(target))
        write(target, c.source_text)
        files[rel]=c.sha256
    end
    fixed=input_modes(
        cases["equipment-fixed"];
        version = p["schema"]=="r9-distributed-study-protocol-v3" ? 3 : 2,
    )
    all(fixed["heat_direction"] .<= fixed["u_H"]) ||
        error("Closed heat direction conflicts with topology")
    text=call(lib, :r4_text, Dict(k=>call(lib, :r2_extract, v) for (k, v) in fixed))
    write(safe(out, "fixed-modes.toml"), text)
    files["fixed-modes.toml"]=hashfile(safe(out, "fixed-modes.toml"))
    meta=Dict(
        "schema"=>"r9-distributed-study-v1",
        "protocol_path"=>protocol_path,
        "origin"=>"synthetic",
        "files"=>files,
        "protocol"=>p,
        "methods"=>p["methods"],
        "optimization_performed_at_freeze"=>false,
        "git_commit"=>readchomp(`git -C $root rev-parse HEAD`),
        "git_status"=>read(`git -C $root status --porcelain=v1`, String),
        "created_utc"=>string(now(UTC)),
        "julia_version"=>string(VERSION),
    )
    toml(safe(out, "manifest.toml"), meta)
    check(out)
end

"""只读核对冻结身份、文件字节、输入与离散规则，不获取商业许可。"""
function check(out)
    m=TOML.parsefile(safe(out, "manifest.toml"))
    m["schema"]=="r9-distributed-study-v1" &&
    m["origin"]=="synthetic" &&
    !m["optimization_performed_at_freeze"] || error("Freeze identity")
    for (rel, h) in m["files"]
        hashfile(safe(out, rel))==h || error("Frozen bytes changed: $rel")
    end
    p=protocol(safe(out, "code"), get(m, "protocol_path", "configs/r9/distributed-study.toml"))
    p==m["protocol"] && m["methods"]==p["methods"] || error("Frozen protocol differs")
    for policy in ("fixed", "joint")
        m["files"]["inputs/equipment-"*policy*".toml"]==p[policy*"_input_sha256"] ||
            error("Input identity")
    end
    d=TOML.parsefile(safe(out, "inputs/equipment-fixed.toml"))
    version=p["schema"]=="r9-distributed-study-protocol-v1" ? 1 :
            p["schema"]=="r9-distributed-study-protocol-v2" ? 2 : 3
    expected=Dict(
        k=>[collect(row) for row in eachrow(v)] for (k, v) in input_modes((; data = d); version)
    )
    TOML.parsefile(safe(out, "fixed-modes.toml"))==expected ||
        error("Mode content differs from input-only rule")
    m
end

function optimizer(entry, p)
    Core.eval(@__MODULE__, :(using JuMP))
    if entry["solver"]=="Clarabel"
        Core.eval(@__MODULE__, :(using Clarabel))
        return Base.invokelatest() do
            JuMP.optimizer_with_attributes(Clarabel.Optimizer, collect(p["clarabel"])...)
        end
    end
    Core.eval(@__MODULE__, :(using Gurobi))
    Base.invokelatest() do
        env=Ref{Any}(nothing)
        maker=()->begin
            env[]===nothing && (env[]=Gurobi.Env(Dict{String,Any}("OutputFlag"=>0)))
            Gurobi.Optimizer(env[])
        end
        JuMP.optimizer_with_attributes(maker, collect(p["gurobi"])...)
    end
end

"""运行单个冻结方法；所有原值保留，启动/封存异常单列，不能覆盖后挑选结果。"""
function run(out, id; process_start = clock())
    VERSION==v"1.12.6" || error("Julia version")
    m=check(out)
    p=m["protocol"]
    entry=only(x for x in m["methods"] if x["id"]==id)
    hashfile(@__FILE__)==m["files"]["code/scripts/r9_distributed_study.jl"] ||
        error("Use frozen runner")
    target=safe(out, "runs/"*id)
    ispath(target) && error("Do not overwrite a method")
    mkpath(target)
    receipt=Dict{String,Any}(
        "schema"=>"r9-distributed-study-receipt-v1",
        "entry"=>entry,
        "manifest_sha256"=>hashfile(safe(out, "manifest.toml")),
        "start_utc"=>string(now(UTC)),
        "budget_sec"=>p["budget_sec"],
        "status"=>"not_started",
        "central_solution_injected"=>false,
    )
    try
        lib=library(safe(out, "code"))
        c=call(lib, :load_r9_trading_case, safe(out, "inputs/"*entry["case"]*".toml"))
        modes=entry["domain"]=="fixed_modes" ?
              Dict(
            k=>call(lib, :r4_matrix, v) for (k, v) in TOML.parsefile(safe(out, "fixed-modes.toml"))
        ) : nothing
        factory=optimizer(entry, p)
        remaining=p["budget_sec"]-p["archive_reserve_sec"]-(clock()-process_start)
        remaining>0 || error("No budget remains after loading")
        r=if entry["method"]=="central"
            call(lib, :solve_r9_trading_case, c; optimizer = factory, modes, budget_sec = remaining)
        else
            spec=call(
                lib,
                :R9DistributedSpec;
                algorithm = entry["domain"]=="fixed_modes" ? :r9_boundary_admm_fixed_v1 :
                            :r9_boundary_admm_mip_v1,
                rho = p["rho"],
                max_iterations = p["max_iterations"],
            )
            call(
                lib,
                :solve_r9_distributed,
                c;
                optimizer = factory,
                modes,
                spec,
                budget_sec = remaining,
                objective_record = Symbol(get(p, "objective_record", "reported")),
                on_raw_result = r->toml(joinpath(target, "raw-before-validation.toml"), r),
            )
        end
        receipt["status"]=r["status"]
        receipt["validation"]=r["validation"]
        receipt["method_elapsed_sec"]=clock()-process_start
        receipt["method_budget_pass"]=receipt["method_elapsed_sec"]<=p["budget_sec"]
        toml(joinpath(target, "raw-result.toml"), r)
        receipt["raw_result_sha256"]=hashfile(joinpath(target, "raw-result.toml"))
        saver=entry["method"]=="central" ? :save_r9_trading_run : :save_r9_distributed_run
        path=call(lib, saver, c, r; directory = target, run_id = "record")
        receipt["record"]="record"
        receipt["record_manifest_sha256"]=hashfile(joinpath(path, "hashes.toml"))
        receipt["packages"]=Dict(
            info.name=>string(info.version) for (_, info) in Pkg.dependencies() if
            info.name in ("JuMP", "MathOptInterface", "Clarabel", "Gurobi", "Gurobi_jll")
        )
        println(id, ": ", r["status"], "; original values saved")
    catch err
        err isa InterruptException && rethrow()
        receipt["status_before_archive_error"]=receipt["status"]
        receipt["status"]="startup_or_archive_error"
        receipt["error_type"]=string(typeof(err))
        receipt["error_summary"]=replace(
            sprint(showerror, err),
            r"[A-Za-z]:[\\/][^\s\n]*"=>"[local path]",
        )
        showerror(stderr, err, catch_backtrace())
        println(stderr)
    end
    receipt["process_elapsed_sec"]=clock()-process_start
    checkpoint=joinpath(target, "raw-before-validation.toml")
    isfile(checkpoint) && (receipt["raw_before_validation_sha256"]=hashfile(checkpoint))
    receipt["process_budget_pass"]=receipt["process_elapsed_sec"]<=p["budget_sec"]
    toml(joinpath(target, "receipt.toml"), receipt)
    haskey(receipt, "record") || error("Incomplete method retained")
    receipt
end

function main(args)
    length(args)==3 && args[1]=="freeze" && return freeze(abspath(args[2]), abspath(args[3]))
    length(args)==2 && args[1]=="check" && return check(abspath(args[2]))
    length(args)==3 &&
        args[1]=="run" &&
        return run(
            abspath(args[2]),
            args[3];
            process_start = getfield(parentmodule(@__MODULE__), :R9_DISTRIBUTED_STUDY_START),
        )
    error("usage: r9_distributed_study.jl freeze PARENT NEW_STUDY | check STUDY | run STUDY METHOD")
end
end
abspath(PROGRAM_FILE)==abspath(@__FILE__) && R9DistributedStudy.main(ARGS)
