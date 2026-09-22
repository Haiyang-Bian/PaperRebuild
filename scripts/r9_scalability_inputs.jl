# 只准备并核对输入和实际模型类型，不启动优化、申请商业许可或改变历史结果。
module R9ScalabilityInputs
using PaperRebuild, TOML, SHA, Dates, JuMP
include("r9_distributed_study.jl")
using .R9DistributedStudy.R9TradingStudy: safe, hashfile, toml
const ROOT=normpath(joinpath(@__DIR__, ".."))
const PROTOCOL="configs/r9/scalability-inputs.toml"

function protocol()
    p=TOML.parsefile(joinpath(ROOT, PROTOCOL))
    p["schema"]=="r9-scalability-input-protocol-v1" && p["origin"]=="synthetic" ||
        error("Input protocol identity")
    p["multipliers"]==[1, 2, 4] && p["parent_aggregators"]==8 || error("Count protocol changed")
    !p["author_input_equivalence"] &&
    !p["formal_methods_started"] &&
    !p["payoff_or_AG0_equivalence"] || error("Claim boundary")
    p["fixed_mode_rule_version"]==3 || error("Mode rule changed")
    p
end

function inventory(c, modes)
    fixed=build_r9_trading_model(c; modes)
    mixed=build_r9_trading_model(c)
    count(is_binary, all_variables(fixed.model))==0 || error("Fixed modes are not continuous")
    contract=r9_boundary_contract(c)
    Dict{String,Any}(
        "aggregators"=>length(c.data["actors"])-1,
        "fixed_class"=>fixed.model_class,
        "mixed_class"=>mixed.model_class,
        "fixed_variables"=>num_variables(fixed.model),
        "mixed_variables"=>num_variables(mixed.model),
        "mixed_binaries"=>count(is_binary, all_variables(mixed.model)),
        "boundary_scalar_count"=>length(contract.lower),
        "cost_scale_CNY"=>PaperRebuild.r9_distributed_cost_scale(c),
        "optimization_performed"=>false,
    )
end

function prepare(source, out)
    ispath(out) && error("Do not overwrite prepared inputs")
    p=protocol()
    parent=load_r9_trading_case(source)
    parent.sha256==p["parent_sha256"] || error("Wrong frozen parent input")
    length(parent.data["actors"])==p["parent_aggregators"]+1 &&
    parent.data["T"]==p["T"] &&
    parent.data["dt_h"]==p["dt_h"] &&
    parent.data["electric"]["nodes"]==p["electric_nodes"] &&
    parent.data["heat"]["nodes"]==p["heat_nodes"] || error("Parent scope differs")
    modes=R9DistributedStudy.input_modes(parent; version = p["fixed_mode_rule_version"])
    derived=[r9_split_aggregators(parent, k) for k in p["multipliers"]]
    counts=[inventory(x.case, modes) for x in derived]
    all(x->x["mixed_binaries"]==counts[1]["mixed_binaries"], counts) ||
        error("Discrete choices changed")
    all(
        x->isapprox(x["cost_scale_CNY"], counts[1]["cost_scale_CNY"]; rtol = 1e-12, atol = 0),
        counts,
    ) || error("Cost scale changed")
    mkpath(out)
    files=Dict{String,String}()
    function put(rel, text)
        write(safe(out, rel), text)
        files[rel]=hashfile(safe(out, rel))
    end
    put("parent.toml", parent.source_text)
    put("protocol.toml", read(joinpath(ROOT, PROTOCOL), String))
    put(
        "fixed-modes.toml",
        PaperRebuild.r4_text(Dict(k=>PaperRebuild.r2_extract(v) for (k, v) in modes)),
    )
    for (x, count) in zip(derived, counts)
        id="ag"*string(count["aggregators"])
        put(id*".toml", x.case.source_text)
        put(id*"-mapping.toml", PaperRebuild.r4_text(x.mapping))
        put(
            id*"-audit.toml",
            PaperRebuild.r4_text(
                merge(audit_r9_aggregator_split(parent, x.case, x.mapping), count),
            ),
        )
    end
    source_hashes=PaperRebuild.r9_trading_science_hashes()
    for rel in (
        PROTOCOL,
        "scripts/r9_scalability_inputs.jl",
        "scripts/r9_distributed_study.jl",
        "scripts/r9_trading_study.jl",
    )
        source_hashes[rel]=hashfile(safe(ROOT, rel))
    end
    toml(
        safe(out, "manifest.toml"),
        Dict(
            "schema"=>"r9-scalability-inputs-v1",
            "origin"=>"synthetic",
            "created_utc"=>string(now(UTC)),
            "julia_version"=>string(VERSION),
            "git_commit"=>readchomp(`git -C $ROOT rev-parse HEAD`),
            "git_dirty"=>!isempty(read(`git -C $ROOT status --porcelain=v1`, String)),
            "files"=>files,
            "source_hashes"=>source_hashes,
            "optimization_performed"=>false,
            "replay_scope"=>"current_implementation_input_checks; no_frozen_solver_replay",
        ),
    )
    check(out)
end

function check(out)
    m=TOML.parsefile(safe(out, "manifest.toml"))
    m["schema"]=="r9-scalability-inputs-v1" && !m["optimization_performed"] ||
        error("Input receipt identity")
    for (rel, h) in m["files"]
        hashfile(safe(out, rel))==h || error("Prepared bytes changed: $rel")
    end
    p=TOML.parsefile(safe(out, "protocol.toml"))
    p==protocol() || error("Prepared rules differ from declared protocol")
    parent=load_r9_trading_case(safe(out, "parent.toml"))
    parent.sha256==p["parent_sha256"] || error("Parent hash differs")
    modes=R9DistributedStudy.input_modes(parent; version = p["fixed_mode_rule_version"])
    TOML.parsefile(safe(out, "fixed-modes.toml"))==Dict(
        k=>PaperRebuild.r2_extract(v) for (k, v) in modes
    ) || error("Modes differ")
    expected=Set(["parent.toml", "protocol.toml", "fixed-modes.toml"])
    for k in p["multipliers"]
        id="ag"*string(p["parent_aggregators"]*k)
        union!(expected, [id*".toml", id*"-mapping.toml", id*"-audit.toml"])
        child=load_r9_trading_case(safe(out, id*".toml"))
        mapping=TOML.parsefile(safe(out, id*"-mapping.toml"))
        mapping["multiplier"]==k || error("Count mismatch")
        observed=merge(audit_r9_aggregator_split(parent, child, mapping), inventory(child, modes))
        observed==TOML.parsefile(safe(out, id*"-audit.toml")) || error("Rebuilt audit differs")
    end
    Set(keys(m["files"]))==expected || error("Incomplete input inventory")
    println("8/16/32 aggregator input checks passed; no optimization performed.")
    m
end

function main(args)
    VERSION==v"1.12.6" || error("Use Julia 1.12.6")
    length(args)==3 && args[1]=="prepare" && return prepare(abspath(args[2]), abspath(args[3]))
    length(args)==2 && args[1]=="check" && return check(abspath(args[2]))
    error("Usage: r9_scalability_inputs.jl prepare PARENT_INPUT NEW_DIRECTORY | check DIRECTORY")
end
end
abspath(PROGRAM_FILE)==abspath(@__FILE__) && R9ScalabilityInputs.main(ARGS)
