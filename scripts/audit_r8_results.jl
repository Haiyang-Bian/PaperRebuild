using CSV, TOML, SHA
include("r8_tradeoff_study.jl")

function r8_residual_table(x)
    rows=NamedTuple[]
    for item in x.items
        r=x.records[item["id"]].result
        function visit(v, path)
            if v isa AbstractDict
                if all(haskey(v, k) for k in ("residual", "tolerance", "pass"))
                    push!(
                        rows,
                        (
                            id = item["id"],
                            run_id = r["run_id"],
                            path = path,
                            equation = string(get(v, "id", "unlabelled")),
                            residual = Float64(v["residual"]),
                            tolerance = Float64(v["tolerance"]),
                            pass = Bool(v["pass"]),
                        ),
                    )
                end
                for k in sort!(collect(keys(v)))
                    visit(v[k], path*"/"*k)
                end
            elseif v isa AbstractVector
                for (j, z) in enumerate(v)
                    visit(z, path*"/"*string(j))
                end
            end
        end
        visit(r["validation"], "validation")
    end
    rows
end

function r8_comparison_table(x)
    rows=NamedTuple[]
    function compare(kind, a, b; ordering = false)
        ra, rb=x.records[a["id"]].result, x.records[b["id"]].result
        pa, pb=ra["validation"]["primary"], rb["validation"]["primary"]
        av, bv=get(pa, "objective_value", missing), get(pb, "objective_value", missing)
        status="inconclusive"
        delta=missing
        if pa["objective_complete"]&&pb["objective_complete"]
            delta=(av-bv)/max(1, abs(av), abs(bv))
            status=(ordering ? delta>=-1e-4 : abs(delta)<=1e-4) ? "supported" : "contradiction"
        elseif ra["primary"]["status"]==rb["primary"]["status"]=="infeasible_certified"
            status="both_infeasible"
        elseif ordering && ra["primary"]["status"]=="infeasible_certified"&&pb["model_pass"]
            status="strict_infeasible_loose_feasible"
        elseif ordering&&pa["model_pass"]&&rb["primary"]["status"]=="infeasible_certified"
            status="contradiction"
        end
        push!(
            rows,
            (
                kind = kind,
                left = a["id"],
                right = b["id"],
                left_value = av,
                right_value = bv,
                relative_difference = delta,
                judgement = status,
            ),
        )
    end
    for a in x.items
        if a["solver"]=="HiGHS"
            b=filter(
                y->y["solver"]=="Gurobi"&&y["case_sha256"]==a["case_sha256"] &&
                   y["flow_sha256"]==a["flow_sha256"]&&y["spec_sha256"]==a["spec_sha256"],
                x.items,
            )
            length(b)==1||error("同输入求解器配对缺失")
            compare("same_model_solver", a, only(b))
        end
        if a["mode"]=="threshold"
            bs=filter(
                y->y["mode"]=="threshold"&&y["solver"]==a["solver"] &&
                   y["case_sha256"]==a["case_sha256"]&&y["flow_sha256"]==a["flow_sha256"] &&
                   y["limit_MWh"]>a["limit_MWh"]&&y["resource"]==a["resource"],
                x.items,
            )
            isempty(bs)||compare(
                "nested_threshold",
                a,
                first(sort(bs; by = y->y["limit_MWh"]));
                ordering = true,
            )
        end
    end
    rows
end

function r8_heat_boundary_table(x)
    rows=NamedTuple[]
    for item in x.items
        item["resource"]=="no_net_heat_charge" || continue
        d=item["normal"]
        h=d["heat"]
        p=only(h["pipes"])
        d["periods"]>=2 || error("热边界证书至少需要两步输运")
        d["heat_terminal_rule"]=="pipe_inventory_initial" || error("热边界证书要求周期库存")
        all(==(first(h["ambient_K"])), h["ambient_K"]) || error("证书要求恒定环境")
        a=first(h["ambient_K"])
        mass=h["rho_kg_m3"]*p["volume_S_m3"]
        mass==h["rho_kg_m3"]*p["volume_R_m3"] || error("证书要求同质量供回水")
        flow=first(p["normal_flow_kg_s"])
        all(==(flow), p["normal_flow_kg_s"]) && abs(flow*3600d["dt_h"]/mass-1)<1e-12 ||
            error("证书仅适用于一步全换水")
        for kind in ("pipe", "source", "load")
            PaperRebuild.r7_unpack(item["flow"]["normal_flow"], kind*"_min") ==
            PaperRebuild.r7_unpack(item["flow"]["normal_flow"], kind*"_max") ||
                error("此证书不覆盖自由流量")
        end
        all(==(flow), PaperRebuild.r7_unpack(item["flow"]["normal_flow"], "pipe_min")) ||
            error("证书固定流量与管道参考不一致")
        p["UA_S_W_K"]==p["UA_R_W_K"] || error("证书要求同UA")
        β=3600d["dt_h"]*p["UA_S_W_K"]/(mass*h["c_J_kgK"])
        k=β==0 ? 1.0 : -expm1(-β)/β
        W=length(d["probabilities"])
        for w in 1:W
            S=only(p["initial_S_profiles"][w]["temperature_K"])
            R=only(p["initial_R_profiles"][w]["temperature_K"])
            load=only(unique(h["load_MW"][2]))
            δ=load/(h["c_J_kgK"]/1e6*flow)
            abs((S-R)-δ)<1e-10 || error("不是冻结的无损均温初态")
            # 库存上界给源温上界；下一步出口经历整步散热，回水由负荷温降决定。
            source_upper=a+(S-a)/k
            supply_out_upper=a+(source_upper-a)*exp(-β)
            return_end_upper=a+(supply_out_upper-δ-a)*k
            deficit=R-return_end_upper
            margin=mass*h["c_J_kgK"]/3.6e9*deficit
            # 独立水团回放同一上界输入；不求解，不修改原运行。
            ps=PaperRebuild.r7_pipe_state([mass], [S])
            pr=PaperRebuild.r7_pipe_state([mass], [R])
            for t in 1:d["periods"]
                os=PaperRebuild.r7_pipe_step(
                    ps;
                    mass_flow_kg_s = flow,
                    inlet_K = source_upper,
                    ambient_K = a,
                    dt_h = d["dt_h"],
                    cp_J_kgK = h["c_J_kgK"],
                    UA_W_K = p["UA_S_W_K"],
                    reference_K = h["S_min_K"],
                )
                ps=os.state
                return_step=PaperRebuild.r7_pipe_step(
                    pr;
                    mass_flow_kg_s = flow,
                    inlet_K = os.outlet_mean_K-δ,
                    ambient_K = a,
                    dt_h = d["dt_h"],
                    cp_J_kgK = h["c_J_kgK"],
                    UA_W_K = p["UA_R_W_K"],
                    reference_K = h["R_min_K"],
                )
                pr=return_step.state
            end
            replay=PaperRebuild.r7_pipe_inventory(
                pr;
                cp_J_kgK = h["c_J_kgK"],
                reference_K = h["R_min_K"],
            ).mean_K
            abs(replay-return_end_upper)<=1e-9 || error("解析热边界与独立回放矛盾")
            push!(
                rows,
                (
                    id = item["id"],
                    scenario = w,
                    source_upper_K = source_upper,
                    return_end_upper_K = return_end_upper,
                    required_return_K = R,
                    deficit_K = deficit,
                    inventory_deficit_MWh = margin,
                    replay_return_K = replay,
                    infeasibility_supported = margin>1e-6,
                    scope = "normal_fixed_flow_heat_boundary_only",
                ),
            )
        end
    end
    rows
end

function r8_audit_create(report, dest)
    ispath(dest)&&error("不覆盖R8审计")
    x=r8_archive_check(report)
    t=r8_study_tables(x)
    for (p, rows) in (("summary.csv", t.rows), ("events.csv", t.events))
        io=IOBuffer()
        CSV.write(io, rows)
        take!(io)==read(joinpath(report, p)) || error("R8报告表与独立原值重读不一致：$p")
    end
    mkpath(dest)
    residuals=r8_residual_table(x)
    # 仅按完整行分片，保留所有原始残差，避免公开包出现超大单文件。
    parts=String[]
    for (k, start) in enumerate(1:5000:length(residuals))
        p="residuals-"*lpad(string(k), 3, '0')*".csv"
        CSV.write(joinpath(dest, p), residuals[start:min(start+4999, length(residuals))])
        push!(parts, p)
    end
    CSV.write(joinpath(dest, "comparisons.csv"), r8_comparison_table(x))
    CSV.write(joinpath(dest, "heat-boundary.csv"), r8_heat_boundary_table(x))
    cp(@__FILE__, joinpath(dest, "audit-source.jl"))
    write(
        joinpath(dest, "audit.toml"),
        PaperRebuild.r7_text(
            Dict(
                "schema"=>"r8-tradeoff-audit-v1",
                "origin"=>"synthetic",
                "report_manifest_sha256"=>r8_file_hash(joinpath(report, "report-hashes.toml")),
                "residual_parts"=>parts,
                "residual_count"=>length(residuals),
                "files"=>r8_archive_files(dest),
            ),
        ),
    )
    println("R8 raw values, printed tables, residuals and comparable pairs checked.")
end

if abspath(PROGRAM_FILE)==@__FILE__
    length(ARGS)==2||error("usage: audit_r8_results.jl REPORT NEW_AUDIT")
    r8_audit_create(abspath(ARGS[1]), abspath(ARGS[2]))
end
