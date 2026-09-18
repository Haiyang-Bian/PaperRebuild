using PaperRebuild, TOML, CSV, SHA

length(ARGS) in (1, 2) || error("参数：study.toml [新报告目录]")
study_path = abspath(ARGS[1])
study = TOML.parsefile(study_path)
root = normpath(joinpath(@__DIR__, ".."))
batch = dirname(study_path)
output = length(ARGS) == 2 ? ARGS[2] : joinpath(root, "results", "summaries", "r4-heat")
ispath(output) && error("不覆盖报告")
config = joinpath(root, "configs", "r4", "heat-compatibility-study.toml")
study["config_sha256"] == bytes2hex(sha256(read(config))) || error("冻结规则改变")
rules = study["rules"]
expected = Set(
    x["id"] * "--" * band["id"] * "--" * stage for
    x in rules["records"], band in rules["bands"], stage in rules["stages"]
)
length(study["records"]) == length(expected) &&
Set(x["id"] for x in study["records"]) == expected || error("阶段清单缺失或重复")
for (rel, hash) in study["source_hashes"]
    bytes2hex(sha256(read(joinpath(batch, "snapshot", rel)))) == hash || error("源码快照改变")
end
parents = Dict(x["id"] => x for x in rules["records"])
bands = Dict(x["id"] => x for x in rules["bands"])
outcomes = Dict(x["id"] => x for x in study["records"])
parent_runs = Dict{String,Any}()
for (id, rec) in parents
    path = joinpath(root, rules["parent_batch"], id)
    bytes2hex(sha256(read(joinpath(path, "result.toml")))) == rec["result_sha256"] ||
        error("父结果哈希改变")
    parent_runs[id] = read_r4_run(path)
end
summary = NamedTuple[]
residuals = NamedTuple[]
states = NamedTuple[]
intervals = NamedTuple[]
node_intervals = NamedTuple[]

"""给定冻结热量和温差包络，解析提取质量流的必要区间；只用于可核查的负结果解释。"""
function heat_mass_interval(heat, lower_delta, upper_delta, cp, tolerance, lo, hi)
    lo = max(lo, (heat - tolerance) / (cp * upper_delta))
    if lower_delta > 0
        hi = min(hi, (heat + tolerance) / (cp * lower_delta))
    elseif heat + tolerance < 0
        hi = -Inf
    end
    return lo, hi
end

for x in study["records"]
    id, parent_id, band_id, stage = (x[k] for k in ("id", "parent", "band", "stage"))
    old = parent_runs[parent_id]
    c, parent = old.case, old.result
    pmeta = parents[parent_id]
    band = bands[band_id]
    fixed = startswith(stage, "fixed")
    level = endswith(stage, "envelope") ? :envelope : :mixing
    spec = R4HeatCompatibilitySpec(;
        level,
        fixed_mass = fixed,
        supply_K = Tuple(band["supply_K"]),
        return_K = Tuple(band["return_K"]),
    )
    r = Dict{String,Any}()
    val = Dict{String,Any}("pass" => false, "checked" => false, "rows" => [])
    if x["saved"]
        path = joinpath(batch, id)
        bytes2hex(sha256(read(joinpath(path, "reconstruction.toml")))) == x["sha256"] ||
            error("热核查结果改变")
        loaded = read_r4_heat_run(path)
        r, val = loaded.result, loaded.validation
        loaded.case.sha256 == c.sha256 == pmeta["input_sha256"] || error("输入不同")
        r["parent_sha256"] == PaperRebuild.r4_heat_parent_hash(parent) || error("父调度不同")
        r["source_hashes_at_solve"] == study["source_hashes"] || error("科学源码混用")
        r["spec"] == PaperRebuild.r4_heat_spec(spec) || error("检查范围不同")
        isequal(r["operating_cost"], parent["operating_cost"]) || error("费用被改写")
        r["status"] == x["status"] && val["pass"] == x["pass"] || error("判定不同")
        get(r, "objective_type", "") == "feasibility" || error("错误目标")
    else
        stage in ("fixed_mixing", "free_mixing") &&
        x["status"] == "necessary_condition_infeasible" || error("非法跳过")
        prerequisite =
            parent_id * "--" * band_id * "--" * (fixed ? "fixed_envelope" : "free_envelope")
        outcomes[prerequisite]["status"] == "solver_infeasible" || error("跳过没有必要条件证据")
    end
    for row in val["rows"]
        push!(
            residuals,
            (;
                run_id = id,
                parent = parent_id,
                band = band_id,
                stage,
                equation = row["id"],
                entity = row["index"],
                t = row["time"],
                residual = row["residual"],
                tolerance = row["tolerance"],
                normalized = row["residual"]/row["tolerance"],
                unit = row["unit"],
                pass = row["pass"],
            ),
        )
    end
    mass_change = NaN
    if haskey(r, "values")
        value = r["values"]
        mass_change = maximum(
            abs(value[k][i][t] - parent["values"][k][i][t]) for
            k in ("m_pipe", "m_source", "m_load") for i in eachindex(value[k]) for
            t in eachindex(value[k][i])
        )
        z = PaperRebuild.r4_heat_data(c, parent)
        for (k, rows) in value, i in eachindex(rows), t in eachindex(rows[i])
            ismass = startswith(k, "m_")
            before = ismass ? parent["values"][k][i][t] : NaN
            push!(
                states,
                (;
                    run_id = id,
                    parent = parent_id,
                    band = band_id,
                    stage,
                    variable = k,
                    entity = i,
                    t,
                    value = rows[i][t],
                    old_value = before,
                    unit = ismass ? "kg/s" : "K",
                ),
            )
        end
    end
    push!(
        summary,
        (;
            run_id = id,
            parent = parent_id,
            case = pmeta["case"],
            policy = pmeta["policy"],
            electric = pmeta["electric"],
            band = band_id,
            stage,
            status = x["status"],
            saved = x["saved"],
            termination = get(r, "termination", "NOT_SOLVED"),
            independent_checked = val["checked"],
            pass = val["pass"],
            detailed_temperature_pass = level == :mixing && val["pass"],
            parent_model_A1 = old.validation["model_pass"],
            parent_electric_A1 = old.validation["model_pass"] &&
                                 old.validation["electric_original_pass"],
            operating_cost = parent["operating_cost"],
            cost_change = x["saved"] ? 0.0 : NaN,
            max_mass_change_kg_s = mass_change,
            max_normalized_residual = get(val, "max_normalized_residual", NaN),
            elapsed_sec = get(r, "elapsed_sec", 0.0),
            input_sha256 = c.sha256,
        ),
    )
    level == :envelope || continue
    z = PaperRebuild.r4_heat_data(c, parent)
    h = c.data["heat"]
    cp = z.cp
    dp, df = z.p_tol/10, z.f_tol/10
    dmin = max(0, spec.supply_K[1]-spec.return_K[2])
    dmax = spec.supply_K[2]-spec.return_K[1]
    ranges = Dict{Tuple{String,Int,Int},Tuple{Float64,Float64}}()
    for t in 1:z.T
        for (p, pipe) in enumerate(z.pipes)
            lo, hi = 0.0, pipe["flow_max"]*z.on[p, t]
            for heat in (z.q["H_in"][p, t], z.q["H_out"][p, t])
                lo, hi = heat_mass_interval(heat, dmin, dmax, cp, dp, lo, hi)
            end
            lo = max(
                lo,
                (z.Ls[p, t]-dp)/(cp*(spec.supply_K[2]-spec.supply_K[1])),
                (z.Lr[p, t]-dp)/(cp*(spec.return_K[2]-spec.return_K[1])),
            )
            if fixed
                lo = max(lo, z.q["m_pipe"][p, t]-df)
                hi = min(hi, z.q["m_pipe"][p, t]+df)
            end
            ranges[("pipe", p, t)] = (lo, hi)
            push!(
                intervals,
                (;
                    run_id = id,
                    parent = parent_id,
                    band = band_id,
                    stage,
                    kind = "pipe",
                    entity = p,
                    t,
                    lower_kg_s = lo,
                    upper_kg_s = hi,
                    gap_kg_s = max(0, lo-hi),
                    materially_empty = lo-hi>z.f_tol,
                    H_in_MW = z.q["H_in"][p, t],
                    H_out_MW = z.q["H_out"][p, t],
                    supply_loss_MW = z.Ls[p, t],
                    return_loss_MW = z.Lr[p, t],
                    old_mass_kg_s = z.q["m_pipe"][p, t],
                ),
            )
        end
        for i in 1:3,
            (port, Hkey, key) in (("source", "H_src", "m_source"), ("load", "H_D", "m_load"))

            lo, hi = heat_mass_interval(
                z.q[Hkey][i, t],
                max(dmin, h[port*"_delta_min"]),
                min(dmax, h[port*"_delta_max"]),
                cp,
                dp,
                0.0,
                c.data["actors"][i]["port_flow_max"],
            )
            if fixed
                lo=max(lo, z.q[key][i, t]-df)
                hi=min(hi, z.q[key][i, t]+df)
            end
            ranges[(port, i, t)]=(lo, hi)
            push!(
                intervals,
                (;
                    run_id = id,
                    parent = parent_id,
                    band = band_id,
                    stage,
                    kind = port,
                    entity = i,
                    t,
                    lower_kg_s = lo,
                    upper_kg_s = hi,
                    gap_kg_s = max(0, lo-hi),
                    materially_empty = lo-hi>z.f_tol,
                    H_in_MW = z.q[Hkey][i, t],
                    H_out_MW = NaN,
                    supply_loss_MW = NaN,
                    return_loss_MW = NaN,
                    old_mass_kg_s = z.q[key][i, t],
                ),
            )
        end
        for i in 1:3
            inc=findall(p->p["to"]==i, z.pipes)
            out=findall(p->p["from"]==i, z.pipes)
            low=ranges[("source", i, t)][1]+sum(ranges[("pipe", p, t)][1] for p in inc; init = 0) -
                ranges[("load", i, t)][2]-sum(ranges[("pipe", p, t)][2] for p in out; init = 0)
            high=ranges[("source", i, t)][2]+sum(ranges[("pipe", p, t)][2] for p in inc; init = 0) -
                 ranges[("load", i, t)][1]-sum(ranges[("pipe", p, t)][1] for p in out; init = 0)
            push!(
                node_intervals,
                (;
                    run_id = id,
                    parent = parent_id,
                    band = band_id,
                    stage,
                    node = i,
                    t,
                    mass_balance_min_kg_s = low,
                    mass_balance_max_kg_s = high,
                    gap_kg_s = max(0, low, -high),
                    materially_excludes_zero = low>z.f_tol||high < -z.f_tol,
                ),
            )
        end
    end
end
counts=NamedTuple[]
for band in rules["bands"], stage in rules["stages"]
    rows=filter(x->x.band==band["id"]&&x.stage==stage, summary)
    push!(
        counts,
        (;
            band = band["id"],
            stage,
            required = length(rows),
            saved = count(x->x.saved, rows),
            pass = count(x->x.pass, rows),
            solver_infeasible = count(x->x.status=="solver_infeasible", rows),
            skipped_necessary = count(x->x.status=="necessary_condition_infeasible", rows),
            independent_failed = count(x->x.status=="independent_check_failed", rows),
            other = count(
                x->!(
                    x.status in (
                        "solver_infeasible",
                        "necessary_condition_infeasible",
                        "independent_check_failed",
                        "compatible_candidate",
                    )
                ),
                rows,
            ),
        ),
    )
end
mkpath(output)
for (name, rows) in (
    ("comparison.csv", summary),
    ("counts.csv", counts),
    ("residuals-reference10.csv", filter(x->x.band=="reference10", residuals)),
    ("residuals-reference20.csv", filter(x->x.band=="reference20", residuals)),
    ("states.csv", states),
    ("mass-intervals.csv", intervals),
    ("node-intervals.csv", node_intervals),
)
    CSV.write(joinpath(output, name), rows)
end
checks=Dict(
    "required_stage_count"=>length(expected),
    "residual_row_count"=>length(residuals),
    "saved_stage_count"=>count(x->x.saved, summary),
    "parent_count"=>length(parents),
    "band_count"=>length(bands),
    "detailed_free_pass_count"=>count(x->x.stage=="free_mixing"&&x.pass, summary),
    "detailed_fixed_pass_count"=>count(x->x.stage=="fixed_mixing"&&x.pass, summary),
    "interval_contradiction_count"=>count(x->x.materially_empty, intervals),
    "node_interval_contradiction_count"=>count(x->x.materially_excludes_zero, node_intervals),
    "unchanged_controls_and_cost"=>true,
    "parent_historical_states_unchanged"=>true,
    "pressure_dynamics_actual_temperature_loss_checked"=>false,
    "raw_source_hashes"=>Dict(x["id"]=>x["sha256"] for x in study["records"] if x["saved"]),
)
write(joinpath(output, "checks.toml"), PaperRebuild.r4_text(checks))
write(
    joinpath(output, "report.toml"),
    PaperRebuild.r4_text(
        Dict(
            "batch_id"=>study["batch_id"],
            "origin"=>"synthetic",
            "source_commit"=>study["source_commit"],
            "config_sha256"=>study["config_sha256"],
            "study_sha256"=>bytes2hex(sha256(read(study_path))),
            "script_sha256"=>bytes2hex(sha256(read(@__FILE__))),
            "scope"=>"Fixed parent heat, controls, topology and reference losses; explicit project temperature bands; no pressure/dynamics certification.",
            "bands"=>rules["bands"],
            "stages"=>rules["stages"],
        ),
    ),
)
println(
    "R4 heat: ",
    length(summary),
    " stage records; ",
    checks["detailed_free_pass_count"],
    " free-mass detailed candidates; parent controls/cost unchanged.",
)
