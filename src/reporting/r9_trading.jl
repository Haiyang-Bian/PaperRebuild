function r9_trading_path(root, rel)
    !isempty(rel) &&
    !isabspath(rel) &&
    !occursin(':', rel) &&
    !occursin('\\', rel) &&
    all(x->!isempty(x) && x ∉ (".", ".."), split(rel, '/')) || error("非法存档相对路径")
    path=abspath(root)
    for part in split(rel, '/')
        path=joinpath(path, part)
        islink(path) && error("存档不接受符号链接")
    end
    path
end

function r9_trading_inventory(path)
    paths=String[]
    for (directory, dirs, files) in walkdir(path)
        any(islink(joinpath(directory, x)) for x in [dirs; files]) && error("存档不接受符号链接")
        append!(paths, [replace(relpath(joinpath(directory, x), path), '\\'=>'/') for x in files])
    end
    sort(paths)
end

function r9_trading_write_rows(path, rows)
    names=(:equation, :scope, :entity, :t, :residual, :unit, :tolerance, :pass)
    Row=NamedTuple{names,Tuple{String,String,String,Int,Float64,String,Float64,Bool}}
    typed=Row[
        (;
            equation = x["equation"],
            scope = x["scope"],
            entity = x["entity"],
            t = x["t"],
            residual = x["residual"],
            unit = x["unit"],
            tolerance = x["tolerance"],
            pass = x["pass"],
        ) for x in rows
    ]
    CSV.write(path, typed)
end

"""
    save_r9_trading_run(case, result; directory="results/runs/r9-trading", run_id=...)

保存完整阶段原值、输入、费用/状态、逐式残差CSV、源码和锁定环境；禁止覆盖既有目录。
源码必须与求解期间记录一致；manifest最后写入，部分写入的目录保留为未完成证据。
输入与结果为TOML，残差单位仍为MW/MWh/kg/s/pu/CNY；归档哈希检测意外篡改，不是数字签名。
本函数不运行优化，也不把保存动作当成科学验收通过。
"""
function save_r9_trading_run(
    c::R9TradingCase,
    r;
    directory = joinpath("results", "runs", "r9-trading"),
    run_id = string(uuid4()),
)
    occursin(r"^[A-Za-z0-9_-]+$", run_id) || error("运行ID非法")
    r["source_hashes_at_solve"]==r9_trading_science_hashes() && r["source_unchanged"] ||
        error("求解源码已变化，拒绝替换原运行出处")
    val=validate_r9_trading_run(c, r)
    isequal(val, r["validation"]) || error("保存前运行验收不一致")
    r["cost_optimization_complete"]==val["cost_optimization_complete"] ||
        error("总体费用状态被改写")
    path=abspath(joinpath(directory, run_id))
    ispath(path) && error("不覆盖既有运行")
    mkpath(path)
    out=deepcopy(r)
    out["run_id"]=run_id
    write(joinpath(path, "input.toml"), c.source_text)
    mkpath(joinpath(path, "residuals"))
    for (i, s) in enumerate(out["stages"])
        original=r9_trading_checked_stage(c, s)
        isequal(original, s["validation"]) || error("阶段验证原值已变")
        residual_file="residuals/stage-"*lpad(string(i), 2, '0')*".csv"
        r9_trading_write_rows(joinpath(path, residual_file), original["rows"])
        s["validation"]=r9_trading_summary(original)
        s["residual_file"]=residual_file
    end
    write(joinpath(path, "result.toml"), r4_text(out))
    root=normpath(joinpath(@__DIR__, "..", ".."))
    for (rel, hash) in r["source_hashes_at_solve"]
        source=r9_trading_path(root, rel)
        bytes2hex(sha256(read(source)))==hash || error("快照源文件发生并发变化")
        target=r9_trading_path(path, "snapshot/"*rel)
        mkpath(dirname(target))
        cp(source, target)
    end
    hashes=Dict(
        rel=>bytes2hex(sha256(read(r9_trading_path(path, rel)))) for
        rel in r9_trading_inventory(path)
    )
    write(
        joinpath(path, "hashes.toml"),
        r4_text(Dict("schema"=>"r9-trading-archive-v1", "files"=>hashes)),
    )
    path
end

function r9_trading_check_files(path)
    meta=TOML.parsefile(joinpath(path, "hashes.toml"))
    meta["schema"]=="r9-trading-archive-v1" || error("运行存档版本错误")
    hashes=meta["files"]
    Set(r9_trading_inventory(path))==union(Set(keys(hashes)), Set(["hashes.toml"])) ||
        error("存档清单改变")
    for (rel, hash) in hashes
        bytes2hex(sha256(read(r9_trading_path(path, rel))))==hash || error("存档文件被修改：$rel")
    end
    hashes
end

function r9_trading_read_current(path)
    hashes=r9_trading_check_files(path)
    c=load_r9_trading_case(joinpath(path, "input.toml"))
    r=TOML.parsefile(joinpath(path, "result.toml"))
    for (rel, hash) in r["source_hashes_at_solve"]
        get(hashes, "snapshot/"*rel, "")==hash || error("求解出处与冻结源码不同")
    end
    for stage in r["stages"]
        val=r9_trading_checked_stage(c, stage)
        isequal(r9_trading_summary(val), stage["validation"]) || error("阶段独立验收不符")
        path_csv=r9_trading_path(path, stage["residual_file"])
        types=Dict(
            :equation=>String,
            :scope=>String,
            :entity=>String,
            :t=>Int,
            :residual=>Float64,
            :unit=>String,
            :tolerance=>Float64,
            :pass=>Bool,
        )
        saved=collect(CSV.File(path_csv; types))
        length(saved)==length(val["rows"]) || error("逐式残差覆盖改变")
        for (actual, expected) in zip(saved, val["rows"]), key in keys(types)
            isequal(getproperty(actual, key), expected[string(key)]) || error("残差原值不符：$key")
        end
    end
    val=validate_r9_trading_run(c, r)
    isequal(val, r["validation"]) || error("完整运行验收不符")
    val["cost_optimization_complete"]==r["cost_optimization_complete"] || error("费用完成状态改变")
    primary=r["primary_stage_index"]
    if val["model_pass"]
        ledger=r9_trading_ledger(c, r["stages"][primary]["values"]; p2p = r["operation"]=="central")
        isequal(ledger, r["ledger"]) || error("账本原值不符")
        ledger["system_cost_CNY"]==r["system_cost_CNY"] || error("资源费用口径改变")
    end
    (; case = c, result = r, validation = val)
end

"""
    read_r9_trading_run(directory; frozen=true)

核对完整文件清单/哈希，默认使用该运行冻结的Julia源码重算阶段链、全部残差与账本。
读取和回代不调用优化器，不申请Gurobi许可；frozen=false仅用于显式开发验证。
同时保留原判定与原始状态；返回case、result及validation，完整热物理认证仍为false。
"""
function read_r9_trading_run(path::AbstractString; frozen = true)
    r9_trading_check_files(path)
    if frozen
        wrapper=Module(gensym(:R9TradingFrozen))
        Base.include(wrapper, r9_trading_path(path, "snapshot/src/PaperRebuild.jl"))
        # Julia 1.12的新模块绑定也受world age约束，取绑定和调用都须进入最新世界。
        lib=Base.invokelatest(getfield, wrapper, :PaperRebuild)
        reader=Base.invokelatest(getfield, lib, :r9_trading_read_current)
        checked=Base.invokelatest(reader, path)
        return (;
            case = load_r9_trading_case(joinpath(path, "input.toml")),
            result = checked.result,
            validation = checked.validation,
            validation_source = "frozen_source",
        )
    end
    checked=r9_trading_read_current(path)
    (; checked..., validation_source = "current_source_development")
end

"""
    compare_r9_trading_runs(directories)

只读同输入、同整数控制域的完整运行，逐项列出模型/原电网/热包络/账本与费用状态。
AG0及集中候选都通过声明原关系和预算后，才计算候选资源费用差；跨版本费用差不是最优间隙。
未核实AG0网络时不制造协调收益百分比，热包络通过不表示完整温度场成立。
"""
function compare_r9_trading_runs(paths)
    isempty(paths) && error("比较需要运行")
    runs=read_r9_trading_run.(paths)
    length(unique(x.case.sha256 for x in runs))==1 || error("不同输入不能作同输入比较")
    length(unique(x.result["mode_rule"] for x in runs))==1 || error("不同整数控制域不能混比")
    if first(runs).result["mode_rule"]=="explicit_fixed_integer_choices"
        signatures=[r9_trading_mode_identity(x.case, x.result["stages"]) for x in runs]
        all(==(first(signatures)), signatures) || error("固定整数选择不同，不能混比")
    end
    rows=Dict{String,Any}[]
    for x in runs
        r, v=x.result, x.validation
        primary=r["primary_stage_index"]
        row=Dict{String,Any}(
            "run_id"=>r["run_id"],
            "operation"=>r["operation"],
            "electric"=>r["electric"],
            "status"=>r["status"],
            "model_pass"=>v["model_pass"],
            "electric_original_pass"=>v["electric_original_pass"],
            "heat_energy_mass_pass"=>v["heat_energy_mass_pass"],
            "ledger_pass"=>v["ledger_pass"],
            "adopted_physical_pass"=>v["adopted_physical_pass"],
            "full_thermal_physics_certified"=>false,
            "cost_optimization_complete"=>r["cost_optimization_complete"],
            "elapsed_sec"=>r["elapsed_sec"],
            "wall_budget_pass"=>r["wall_budget_pass"],
            "local_cost_optimization_complete"=>v["local_cost_optimization_complete"],
        )
        haskey(r, "system_cost_CNY") && (row["system_cost_CNY"]=r["system_cost_CNY"])
        if primary>0
            for key in ("solver_objective", "objective_bound", "relative_gap", "bound_upper_excess")
                haskey(r["stages"][primary], key) && (row[key]=r["stages"][primary][key])
            end
        end
        push!(rows, row)
    end
    differences=Dict{String,Any}[]
    for a in rows, b in rows
        a["operation"]=="independent" && b["operation"]=="central" || continue
        valid=a["adopted_physical_pass"] &&
              b["adopted_physical_pass"] &&
              a["wall_budget_pass"] &&
              b["wall_budget_pass"]
        pair=Dict{String,Any}(
            "independent_run"=>a["run_id"],
            "central_run"=>b["run_id"],
            "comparable_feasible_candidates"=>valid,
            "meaning"=>"observed_candidate_resource_cost_difference_not_optimality_gap",
        )
        if valid
            pair["resource_cost_difference_CNY"]=a["system_cost_CNY"]-b["system_cost_CNY"]
            if a["system_cost_CNY"]>0
                pair["resource_cost_difference_percent"]=100pair["resource_cost_difference_CNY"]/a["system_cost_CNY"]
            end
        else
            pair["reason"]="network_physics_or_budget_not_verified"
        end
        push!(differences, pair)
    end
    Dict("input_sha256"=>first(runs).case.sha256, "rows"=>rows, "differences"=>differences)
end
