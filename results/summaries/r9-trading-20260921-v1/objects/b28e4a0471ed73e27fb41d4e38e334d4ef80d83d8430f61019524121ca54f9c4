"""
    validate_r4_network_enumeration(case, result)

独立核验单时段全离散清单、每项计划/原始解/验收及全问题界；遗漏或重复不构成穷举。
不求解。逐项重新计算模型残差和成本，不信任保存的最好候选编号。
"""
function validate_r4_network_enumeration(c::R4Case, r)
    c.data["T"]==1 && r["schema"]=="r4-network-enumeration-v1" && r["input_sha256"]==c.sha256 ||
        error("单时段枚举输入错误")
    expected=Set{String}()
    for e in r4_network_states(c, :electric),
        h in r4_network_states(c, :heat),
        signs in 0:3,
        mode in r4_battery_patterns(c)

        dir=zeros(Int, 3, 1)
        for (i, p) in enumerate(findall(==(1), h))
            dir[p, 1]=(signs>>(i-1))&1
        end
        push!(
            expected,
            PaperRebuild.r4_text(
                Dict("electric"=>e, "heat"=>h, "directions"=>r4_rows(dir), "mode"=>mode),
            ),
        )
    end
    seen=Set{String}()
    best=0
    phys=0
    cost=Inf
    pcost=Inf
    bounded=true
    bounds=Float64[]
    for (i, x) in enumerate(r["records"])
        key=r4_text(Dict(k=>x[k] for k in ("electric", "heat", "directions", "mode")))
        key in expected && !(key in seen) || error("清单重复或非法")
        push!(seen, key)
        if !haskey(x, "raw")
            x["status"]=="not_run_budget" || error("缺失结果状态")
            bounded=false
            continue
        end
        raw=x["raw"]
        isequal(validate_r4_reconfiguration(c, raw), raw["validation"]) || error("逐项验收变化")
        raw["status"]==x["status"] || error("状态不一致")
        p=raw["reconfiguration"]
        p["electric_schedule"]==[[v] for v in x["electric"]] &&
        p["heat_open"]==x["heat"] &&
        p["heat_direction"]==x["directions"] || error("逐项计划错误")
        if haskey(raw, "values")
            maximum(abs, raw["values"]["z"]-x["mode"])<=1e-6 || error("电池模式不符")
            r4_ledger(c, raw["values"])==raw["ledger"] || error("费用账本改变")
        end
        if raw["status"]=="infeasible_certified"
            all(a["termination"]=="INFEASIBLE" for a in raw["solves"]) || error("不可行无证据")
        elseif isfinite(get(raw, "objective_bound", NaN))
            push!(bounds, raw["objective_bound"])
        else
            bounded=false
        end
        if raw["validation"]["model_pass"]
            val=raw["ledger"]["operating_cost"]
            val<cost && (best = i; cost = val)
            if raw["validation"]["electric_original_pass"] && val<pcost
                phys=i
                pcost=val
            end
        end
    end
    seen==expected || error("全离散清单不完整")
    lower=bounded&&!isempty(bounds) ? minimum(bounds) : NaN
    gap=isfinite(cost)&&isfinite(lower) ? abs(cost-lower)/max(1, abs(cost)) : NaN
    actual=Dict(
        "best_model_index"=>best,
        "best_physical_index"=>phys,
        "best_model_cost"=>cost,
        "best_physical_cost"=>pcost,
        "objective_bound"=>lower,
        "relative_gap"=>gap,
        "certificate_A2"=>isfinite(gap)&&gap<=1e-4,
    )
    all(isequal(r[k], v) for (k, v) in actual) || error("枚举摘要不一致")
    return actual
end

"""
    read_r4_network_enumeration(directory)

核验完整文件清单、字节哈希以及全部72项原始结果；不迁移或重算旧实验。
"""
function read_r4_network_enumeration(path::AbstractString)
    hashes=TOML.parsefile(joinpath(path, "hashes.toml"))["sha256"]
    actual=Set(
        replace(relpath(joinpath(d, f), path), '\\'=>'/') for (d, _, fs) in walkdir(path) for
        f in fs if f!="hashes.toml"
    )
    actual==Set(keys(hashes)) || error("枚举文件清单变化")
    for (rel, h) in hashes
        !isabspath(rel)&&!(".." in split(rel, '/')) || error("非法存档路径")
        bytes2hex(sha256(read(joinpath(path, rel))))==h || error("枚举文件哈希变化")
    end
    c=load_r4_case(joinpath(path, "input.toml"))
    r=TOML.parsefile(joinpath(path, "result.toml"))
    return (; case = c, result = r, validation = validate_r4_network_enumeration(c, r))
end
