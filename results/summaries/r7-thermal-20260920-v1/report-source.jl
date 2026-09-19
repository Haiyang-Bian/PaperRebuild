include("r7_thermal_study.jl")

function thermal_audit_tables(dir)
    records=TOML.parsefile(joinpath(dir, "inputs.toml"))["records"]
    ports=IOBuffer()
    comparison=IOBuffer()
    profiles=IOBuffer()
    checks=0
    println(
        ports,
        "group,run_id,node,time,scenario,flow_source_kg_s,source_MW,source_min_MW,source_gap_MW,flow_load_kg_s,planned_heat_MW,load_max_MW,load_gap_MW",
    )
    println(
        comparison,
        "group,highs_MWh,clarabel_MWh,relative_difference,A2_pass,clarabel_bound_available",
    )
    println(profiles, "group,pipe,side,scenario,segment,mass_start_kg,mass_end_kg,temperature_K")
    values=Dict{String,Any}()
    for item in records
        x=thermal_read_frozen(joinpath(dir, item["id"]))
        c=R7RecoveryCase(x.case.data)
        # 用当前更严格的身份/终止状态检查再回代，但不改写原源码或elapsed_sec。
        q=validate_r7_thermal_reconstruction(c, x.parent, x.spec, x.result)
        isequal(q, x.validation) || error("当前重验与原物理判定不同")
        checks+=1
        values[item["id"]]=(x, q)
        s=x.spec
        h=c.data["heat"]
        if s["substeps"]==1 && s["mode"]=="same_dispatch"
            indata=PaperRebuild.r7_thermal_inputs(c, x.parent, s)
            cw=h["c_J_kgK"]/1e6
            for j in 1:indata.J, t in 1:indata.T, w in 1:indata.W
                ms=indata.v["m_source"][j, t]
                ml=indata.v["m_load"][j, t]
                minq=cw*ms*max(h["source_delta_min"][j], h["S_min_K"]-h["R_max_K"])
                maxq=cw*ml*min(h["load_delta_max"][j], h["S_max_K"]-h["R_min_K"])
                println(
                    ports,
                    join(
                        [
                            item["group"],
                            x.result["run_id"],
                            j,
                            t,
                            w,
                            ms,
                            indata.generated[j, t, w],
                            minq,
                            max(0, minq-indata.generated[j, t, w]),
                            ml,
                            indata.served[j, t, w],
                            maxq,
                            max(0, indata.served[j, t, w]-maxq),
                        ],
                        ',',
                    ),
                )
            end
            for p in s["profiles"]
                offset=0.0
                for (i, z) in enumerate(p["segments"])
                    if z["amplitude_K"]==0
                        println(
                            profiles,
                            join(
                                [
                                    item["group"],
                                    p["pipe"],
                                    p["side"],
                                    p["scenario"],
                                    i,
                                    offset,
                                    offset+z["mass_kg"],
                                    z["base_K"],
                                ],
                                ',',
                            ),
                        )
                    end
                    offset+=z["mass_kg"]
                end
            end
        end
    end
    for group in ("thermal-steady", "hot_outlet", "cold_outlet")
        _, h=values[group*"_n16_curtail_heat"]
        x, c=values[group*"_clarabel"]
        diff=abs(h["heat_unserved_MWh"]-c["heat_unserved_MWh"])/max(1, abs(h["heat_unserved_MWh"]))
        diff<=1e-4 && h["thermal_model_pass"] && c["thermal_model_pass"] ||
            error("同模型求解器A2配对失败")
        println(
            comparison,
            join(
                [
                    group,
                    h["heat_unserved_MWh"],
                    c["heat_unserved_MWh"],
                    diff,
                    true,
                    haskey(x.result, "lower_bound_MWh"),
                ],
                ',',
            ),
        )
    end
    checks==39 || error("冻结研究记录不完整")
    for n in (1, 4, 16)
        values["hot_outlet_n$(n)_same_dispatch"][2]["same_dispatch_pass"] ||
            error("热前锋解析例失败")
        cold=values["cold_outlet_n$(n)_curtail_heat"][2]
        cold["thermal_model_pass"] && abs(cold["heat_unserved_MWh"]-1/30)<=1e-6 ||
            error("冷前锋解析值失败")
    end
    Dict(
        "port-audit.csv"=>String(take!(ports)),
        "solver-comparison.csv"=>String(take!(comparison)),
        "profiles.csv"=>String(take!(profiles)),
    )
end

function thermal_report_create(source, dest)
    thermal_check(source)
    ispath(dest)&&error("不覆盖已有热报告")
    tables=thermal_audit_tables(source)
    mkpath(dest)
    cp(source, joinpath(dest, "evidence"))
    for p in ("summary.csv", "trajectory.csv", "rule.toml")
        cp(joinpath(source, p), joinpath(dest, p))
    end
    for (p, t) in tables
        write(joinpath(dest, p), t)
    end
    cp(@__FILE__, joinpath(dest, "report-source.jl"))
    hashes=Dict(
        replace(relpath(joinpath(p, f), dest), '\\'=>'/')=>bytes2hex(sha256(read(joinpath(p, f))))
        for (p, _, fs) in walkdir(dest) for f in fs
    )
    write(joinpath(dest, "files.toml"), PaperRebuild.r7_text(Dict("files"=>hashes)))
    println(
        "39 original thermal records copied with source snapshots, current replay and 3 A2 objective pairs.",
    )
end

function thermal_report_check(dir)
    files=TOML.parsefile(joinpath(dir, "files.toml"))["files"]
    actual=Set(
        replace(relpath(joinpath(p, f), dir), '\\'=>'/') for (p, _, fs) in walkdir(dir) for f in fs
    )
    actual==union(Set(keys(files)), Set(["files.toml"])) || error("热报告文件集合不符")
    for (p, h) in files
        !isabspath(p)&&!occursin(':', p)&&all(s->!(s in ("", ".", "..")), split(p, '/')) ||
            error("路径错误")
        bytes2hex(sha256(read(joinpath(dir, split(p, '/')...))))==h || error("热报告篡改")
    end
    source=joinpath(dir, "evidence")
    thermal_check(source)
    for p in ("summary.csv", "trajectory.csv", "rule.toml")
        read(joinpath(source, p))==read(joinpath(dir, p)) || error("原图源与报告不符")
    end
    for (p, t) in thermal_audit_tables(source)
        read(joinpath(dir, p), String)==t || error("只读审计表不符")
    end
    println(
        "Thermal report source, values, 39 reconstructions, analytic outcomes and comparison tables checked.",
    )
end

if abspath(PROGRAM_FILE)==@__FILE__
    if length(ARGS)==3 && ARGS[1]=="create"
        thermal_report_create(abspath(ARGS[2]), abspath(ARGS[3]))
    elseif length(ARGS)==2 && ARGS[1]=="check"
        thermal_report_check(abspath(ARGS[2]))
    else
        error("usage: report_r7_thermal.jl create RAW NEW_REPORT | check REPORT")
    end
end
