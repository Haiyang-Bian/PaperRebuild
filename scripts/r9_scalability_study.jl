# 先记时，再装载；由独立启动器传入同机单调时钟起点时，连进程启动也纳入预算。
const R9_SCALABILITY_START=time_ns()/1e9
module R9ScalabilityStudy
include("r9_distributed_study.jl")
const S=R9DistributedStudy
using .R9DistributedStudy.R9TradingStudy: safe, hashfile, toml, library, call, clock
using TOML, SHA, Dates, Pkg
const ROOT=normpath(joinpath(@__DIR__, ".."))
const PROTOCOL="configs/r9/scalability-study.toml"
const EXTRA_SNAPSHOT_PATHS=(
    PROTOCOL,
    "configs/r9/distributed-corridor-study.toml",
    "scripts/r9_scalability_study.jl",
    "scripts/run_r9_scalability_batch.jl",
    "scripts/r9_distributed_study.jl",
    "scripts/r9_trading_study.jl",
    "docs/Project.toml",
    "docs/Manifest.toml",
)

function validate_protocol(p)
    p["schema"]=="r9-scalability-study-protocol-v1" && p["origin"]=="synthetic" ||
        error("Study identity")
    p["counts"]==[8, 16, 32] && p["budget_sec"]==600 && p["archive_reserve_sec"]==180 ||
        error("Frozen scale or budget changed")
    p["max_iterations"]==1000 && p["rho"]==1 && p["objective_record"]=="separate" ||
        error("Algorithm rule changed")
    p["initialization"]=="zero_messages_and_scaled_duals" && p["hard_timeout"] ||
        error("Initialization or deadline changed")
    all(
        !p[k] for k in (
            "central_solution_injected",
            "author_input_equivalence",
            "author_algorithm_equivalence",
            "legacy_runtime_comparable",
        )
    ) || error("Claim boundary")
    expected=[
        (n, d, m, s) for n in p["counts"] for
        (d, s) in (("fixed_modes", "Clarabel"), ("mixed_integer", "Gurobi")) for
        m in ("central", "admm")
    ]
    observed=[(x["aggregators"], x["domain"], x["method"], x["solver"]) for x in p["methods"]]
    observed==expected && allunique(x["id"] for x in p["methods"]) ||
        error("Paired methods/order changed")
    all(
        x["id"]=="ag$(x["aggregators"])-$(x["domain"]=="fixed_modes" ? "fixed" : "mip")-$(x["method"])"
        for x in p["methods"]
    ) || error("Method ID does not identify its pair")
    p["archive"]=="single_original_trajectory_plus_final_validation; shared_science_snapshot" ||
        error("Archive rule changed")
    p["timing"]=="fresh_serial_process; launcher_start_to_exit_including_load_JIT_verification_and_archive" ||
        error("Timing rule changed")
    # 沿用前批精度，不以新分组为由放宽任何求解器或研究门槛。
    old=TOML.parsefile(joinpath(ROOT, "configs/r9/distributed-corridor-study.toml"))
    p["clarabel"]==old["clarabel"] && p["gurobi"]==old["gurobi"] ||
        error("Solver precision changed")
    p
end

function input_paths()
    vcat(
        ["parent.toml", "fixed-modes.toml"],
        ["ag$(n)$(suffix).toml" for n in (8, 16, 32) for suffix in ("", "-mapping")],
    )
end

"""优化前冻结12项规则、既有三套输入与单份源码；拒绝覆盖或更换父输入。"""
function freeze(out; root = ROOT)
    ispath(out) && error("Do not overwrite study")
    p=validate_protocol(TOML.parsefile(safe(root, PROTOCOL)))
    parent=safe(root, p["input_package"])
    hashfile(safe(parent, "manifest.toml"))==p["input_manifest_sha256"] ||
        error("Prepared parent changed")
    inputmeta=TOML.parsefile(safe(parent, "manifest.toml"))
    lib=library(root)
    base=call(lib, :load_r9_trading_case, safe(parent, "parent.toml"))
    modes=Dict(
        k=>call(lib, :r4_matrix, v) for (k, v) in TOML.parsefile(safe(parent, "fixed-modes.toml"))
    )
    for n in p["counts"]
        c=call(lib, :load_r9_trading_case, safe(parent, "ag$n.toml"))
        mapping=TOML.parsefile(safe(parent, "ag$n-mapping.toml"))
        call(lib, :audit_r9_aggregator_split, base, c, mapping)
        length(c.data["actors"])==n+1 || error("Actor count changed")
        call(lib, :r9_distributed_modes, c, modes, call(lib, :R9DistributedSpec))
    end
    files=Dict{String,String}()
    hashes=call(lib, :r9_trading_science_hashes)
    for rel in EXTRA_SNAPSHOT_PATHS
        hashes[rel]=hashfile(safe(root, rel))
    end
    # 在创建目录前取得Git来源；沙盒管道失败不留下貌似完整的研究包。
    commit=readchomp(`git -C $root rev-parse HEAD`)
    dirty=!isempty(read(`git -C $root status --porcelain=v1`, String))
    mkpath(out)
    for (rel, h) in hashes
        target=safe(out, "code/"*rel)
        mkpath(dirname(target))
        hashfile(safe(root, rel))==h || error("Concurrent source change")
        cp(safe(root, rel), target)
        files["code/"*rel]=h
    end
    for rel in input_paths()
        hashfile(safe(parent, rel))==inputmeta["files"][rel] ||
            error("Prepared input hash mismatch")
        target=safe(out, "inputs/"*rel)
        mkpath(dirname(target))
        cp(safe(parent, rel), target)
        files["inputs/"*rel]=hashfile(target)
    end
    cp(safe(parent, "manifest.toml"), safe(out, "inputs/prepared-manifest.toml"))
    files["inputs/prepared-manifest.toml"]=p["input_manifest_sha256"]
    toml(
        safe(out, "manifest.toml"),
        Dict(
            "schema"=>"r9-scalability-study-v1",
            "protocol"=>p,
            "methods"=>p["methods"],
            "files"=>files,
            "origin"=>"synthetic",
            "git_commit"=>commit,
            "git_dirty"=>dirty,
            "created_utc"=>string(now(UTC)),
            "julia_version"=>string(VERSION),
            "optimization_performed_at_freeze"=>false,
        ),
    )
    check(out)
end

"""只读检查冻结源码、输入、规则与双向拆分身份，不启动优化器。"""
function check(out; lib = nothing)
    m=TOML.parsefile(safe(out, "manifest.toml"))
    m["schema"]=="r9-scalability-study-v1" &&
    m["origin"]=="synthetic" &&
    !m["optimization_performed_at_freeze"] || error("Freeze identity")
    for (rel, h) in m["files"]
        hashfile(safe(out, rel))==h || error("Frozen bytes changed: $rel")
    end
    p=validate_protocol(TOML.parsefile(safe(out, "code/"*PROTOCOL)))
    p==m["protocol"] && p["methods"]==m["methods"] || error("Method protocol changed")
    lib===nothing && (lib=library(safe(out, "code")))
    expected=Set(
        vcat(
            ["code/"*x for x in keys(call(lib, :r9_trading_science_hashes))],
            ["code/"*x for x in EXTRA_SNAPSHOT_PATHS],
            ["inputs/"*x for x in input_paths()],
            ["inputs/prepared-manifest.toml"],
        ),
    )
    Set(keys(m["files"]))==expected || error("Incomplete or unexpected freeze inventory")
    hashfile(safe(out, "inputs/prepared-manifest.toml"))==p["input_manifest_sha256"] ||
        error("Prepared manifest changed")
    original=TOML.parsefile(safe(out, "inputs/prepared-manifest.toml"))
    for rel in input_paths()
        hashfile(safe(out, "inputs/"*rel))==original["files"][rel] ||
            error("Prepared input identity changed")
    end
    base=call(lib, :load_r9_trading_case, safe(out, "inputs/parent.toml"))
    for n in p["counts"]
        c=call(lib, :load_r9_trading_case, safe(out, "inputs/ag$n.toml"))
        mapping=TOML.parsefile(safe(out, "inputs/ag$n-mapping.toml"))
        call(lib, :audit_r9_aggregator_split, base, c, mapping)
        mapping["multiplier"]==n÷8 || error("Count mapping changed")
    end
    expected=Dict(k=>call(lib, :r2_extract, v) for (k, v) in S.input_modes(base; version = 3))
    TOML.parsefile(safe(out, "inputs/fixed-modes.toml"))==expected || error("Fixed modes changed")
    m
end

"""原始轨迹只写一次；独立核验后的三个根字段另存，不允许替换迭代或候选。"""
function save_raw(path, r)
    ispath(path) && error("Do not overwrite original result")
    toml(path, r)
    hashfile(path)
end
function completion(r)
    Dict{String,Any}(k=>r[k] for k in ("elapsed_sec", "budget_overrun", "validation"))
end
function apply_completion(raw, final)
    Set(keys(final))==Set(("elapsed_sec", "budget_overrun", "validation")) ||
        error("Completion may not replace controls/status")
    isfinite(final["elapsed_sec"]) && final["elapsed_sec"]>=raw["elapsed_sec"]>=0 ||
        error("Completion time moved backward or is not finite")
    final["budget_overrun"]==(final["elapsed_sec"]>raw["budget_sec"]) ||
        error("Completion budget flag changed")
    merge(raw, final)
end

"""一个方法一个新进程；源码共享，原始数值完整保存，不重复复制三份轨迹。"""
function run_method(out, id; process_start = clock())
    VERSION==v"1.12.6" || error("Julia version")
    lib=library(safe(out, "code"))
    m=check(out; lib)
    hashfile(@__FILE__)==m["files"]["code/scripts/r9_scalability_study.jl"] ||
        error("Use frozen runner")
    p=m["protocol"]
    entry=only(x for x in m["methods"] if x["id"]==id)
    target=safe(out, "runs/"*id)
    ispath(target) && error("Do not overwrite method")
    mkpath(target)
    receipt=Dict{String,Any}(
        "schema"=>"r9-scalability-receipt-v1",
        "entry"=>entry,
        "manifest_sha256"=>hashfile(safe(out, "manifest.toml")),
        "start_utc"=>string(now(UTC)),
        "budget_sec"=>p["budget_sec"],
        "archive_reserve_sec"=>p["archive_reserve_sec"],
        "status"=>"not_started",
        "central_solution_injected"=>false,
        "files"=>Dict{String,String}(),
        "julia_version"=>string(VERSION),
        "cpu"=>Sys.CPU_NAME,
        "logical_cpu_count"=>Sys.CPU_THREADS,
        "kernel"=>string(Sys.KERNEL),
        "julia_threads"=>Threads.nthreads(),
    )
    toml(joinpath(target, "started.toml"), receipt)
    rawpath=joinpath(target, "original.toml")
    outer_deadline=process_start+p["budget_sec"]-p["archive_reserve_sec"]
    try
        c=call(lib, :load_r9_trading_case, safe(out, "inputs/ag$(entry["aggregators"]).toml"))
        modes=entry["domain"]=="fixed_modes" ?
              Dict(
            k=>call(lib, :r4_matrix, v) for
            (k, v) in TOML.parsefile(safe(out, "inputs/fixed-modes.toml"))
        ) : nothing
        factory=S.optimizer(entry, p)
        receipt["loading_sec"]=clock()-process_start
        if entry["method"]=="central"
            r=call(
                lib,
                :solve_r9_trading_case,
                c;
                optimizer = factory,
                modes,
                budget_sec = p["budget_sec"],
                deadline = outer_deadline,
            )
            receipt["solver_return_sec"]=clock()-process_start
            receipt["files"]["original.toml"]=save_raw(rawpath, r)
        else
            spec=call(
                lib,
                :R9DistributedSpec;
                algorithm = entry["domain"]=="fixed_modes" ? :r9_boundary_admm_fixed_v1 :
                            :r9_boundary_admm_mip_v1,
                rho = p["rho"],
                max_iterations = p["max_iterations"],
            )
            observer=x->begin
                receipt["raw_callback_enter_sec"]=clock()-process_start
                receipt["files"]["original.toml"]=save_raw(rawpath, x)
                receipt["raw_callback_exit_sec"]=clock()-process_start
            end
            r=call(
                lib,
                :solve_r9_distributed,
                c;
                optimizer = factory,
                modes,
                spec,
                budget_sec = p["budget_sec"],
                deadline = outer_deadline,
                objective_record = :separate,
                on_raw_result = observer,
            )
            receipt["solver_return_sec"]=clock()-process_start
            final=completion(r)
            receipt["files"]["completion.toml"]=save_raw(joinpath(target, "completion.toml"), final)
        end
        r["source_hashes_at_solve"]==call(lib, :r9_trading_science_hashes) &&
        r["source_unchanged"] || error("Science snapshot changed")
        receipt["validation"]=r["validation"]
        receipt["scientific_status"]=r["status"]
        receipt["status"]="record_saved"
        receipt["packages"]=Dict(
            info.name=>string(info.version) for (_, info) in Pkg.dependencies() if
            info.name in ("JuMP", "MathOptInterface", "Clarabel", "Gurobi", "Gurobi_jll")
        )
    catch err
        err isa InterruptException && rethrow()
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
    receipt["process_budget_pass"]=receipt["process_elapsed_sec"]<=p["budget_sec"]
    toml(joinpath(target, "receipt.toml"), receipt)
    println(id, ": ", receipt["status"], "; ", get(receipt, "scientific_status", "unavailable"))
    receipt["status"]=="record_saved" || error("Incomplete method retained")
    receipt
end

"""将实际结果绑定到冻结方法；空轨迹也不能悄悄换算法、预算或目标记录口径。"""
function check_result_rules(r, entry, p)
    r["budget_sec"]==p["budget_sec"] || error("Result budget differs from protocol")
    if entry["method"]=="admm"
        algorithm=entry["domain"]=="fixed_modes" ? "r9_boundary_admm_fixed_v1" :
                  "r9_boundary_admm_mip_v1"
        r["algorithm"]==algorithm && r["schema"]=="r9-distributed-run-v2" ||
            error("Algorithm differs from pair")
        all(r[k]==p[k] for k in ("rho", "max_iterations", "initialization", "objective_record")) ||
            error("Iteration rules differ from protocol")
        haskey(r, "loop_budget_sec") &&
        0<=r["loop_budget_sec"]<=p["budget_sec"]-p["archive_reserve_sec"] ||
            error("Outer loop allocation differs")
    else
        r["operation"]=="central" && r["electric"]=="socp" && length(r["stages"])==1 ||
            error("Central reference model differs")
    end
    true
end

"""从一次原值和仅含核验/时间的完成记录重建结果，再由冻结验证器重算；不优化。"""
function read_method(out, id; lib = nothing, meta = nothing)
    lib===nothing && (lib=library(safe(out, "code")))
    meta===nothing && (meta=check(out; lib))
    entry=only(x for x in meta["methods"] if x["id"]==id)
    target=safe(out, "runs/"*id)
    receipt=TOML.parsefile(safe(target, "receipt.toml"))
    receipt["entry"]==entry && receipt["manifest_sha256"]==hashfile(safe(out, "manifest.toml")) ||
        error("Method identity")
    !receipt["central_solution_injected"] &&
    receipt["budget_sec"]==meta["protocol"]["budget_sec"] || error("Method scope")
    receipt["archive_reserve_sec"]==meta["protocol"]["archive_reserve_sec"] ||
        error("Archive allocation changed")
    isfinite(receipt["process_elapsed_sec"]) && receipt["process_elapsed_sec"]>=0 ||
        error("Invalid elapsed time")
    receipt["process_budget_pass"]==(receipt["process_elapsed_sec"]<=receipt["budget_sec"]) ||
        error("Wall budget changed")
    receipt["status"]=="record_saved" || error("Method did not complete its record")
    expected=entry["method"]=="central" ? Set(["original.toml"]) :
             Set(["original.toml", "completion.toml"])
    Set(keys(receipt["files"]))==expected || error("Record inventory")
    for (rel, h) in receipt["files"]
        hashfile(safe(target, rel))==h || error("Original bytes changed")
    end
    r=TOML.parsefile(safe(target, "original.toml"))
    entry["method"]=="admm" &&
        (r=apply_completion(r, TOML.parsefile(safe(target, "completion.toml"))))
    c=call(lib, :load_r9_trading_case, safe(out, "inputs/ag$(entry["aggregators"]).toml"))
    r["source_unchanged"] && r["source_hashes_at_solve"]==call(lib, :r9_trading_science_hashes) ||
        error("Source identity")
    r["input_sha256"]==c.sha256 && r["status"]==receipt["scientific_status"] ||
        error("Result identity")
    check_result_rules(r, entry, meta["protocol"])
    if entry["domain"]=="fixed_modes"
        modes=TOML.parsefile(safe(out, "inputs/fixed-modes.toml"))
        (entry["method"]=="admm" ? r["fixed_modes"] : only(r["stages"])["fixed_modes"])==modes ||
            error("Paired modes differ")
    else
        (entry["method"]=="admm" ? !haskey(r, "fixed_modes") : r["mode_rule"]=="free_integer") ||
            error("Integer domain changed")
    end
    verify=entry["method"]=="central" ? :validate_r9_trading_run : :validate_r9_distributed
    v=call(lib, verify, c, r)
    isequal(v, r["validation"]) && isequal(v, receipt["validation"]) ||
        error("Independent replay changed validation")
    (; case = c, result = r, validation = v, receipt, entry)
end

function main(args)
    length(args)==2 && args[1]=="freeze" && return freeze(abspath(args[2]))
    length(args)==2 && args[1]=="check" && return check(abspath(args[2]))
    if length(args) in (3, 4) && args[1]=="run"
        start=length(args)==4 ? parse(Float64, args[4]) :
              getfield(parentmodule(@__MODULE__), :R9_SCALABILITY_START)
        isfinite(start) && 0<=clock()-start<600 || error("Invalid shared process clock")
        return run_method(abspath(args[2]), args[3]; process_start = start)
    end
    length(args)==3 && args[1]=="replay" && return read_method(abspath(args[2]), args[3])
    error(
        "Usage: r9_scalability_study.jl freeze NEW_DIRECTORY | check STUDY | run STUDY METHOD [START] | replay STUDY METHOD",
    )
end
end
abspath(PROGRAM_FILE)==abspath(@__FILE__) && R9ScalabilityStudy.main(ARGS)
