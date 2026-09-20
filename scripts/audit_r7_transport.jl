using CSV, TOML, SHA
include("r7_transport_study.jl")

"""只读已保存的逐管调度，逐行核查残差；不重算优化，不修改历史通过标志。"""
function transport_audit_tables(src)
    registry = TOML.parsefile(joinpath(src, "files.toml"))["files"]
    transport_manifest(src) == registry || error("输入证据文件或哈希改变")
    inputs, _ = transport_inputs(src)
    summaries = NamedTuple[]
    residuals = NamedTuple[]
    for item in inputs["records"]
        x = transport_read(joinpath(src, "records", item["id"]))
        q = x.validation
        maxima = Dict("shared" => 0.0, "thermal" => 0.0)
        failed = 0
        for block in ("shared", "thermal")
            haskey(q, block) || continue
            for row in q[block]["rows"]
                get(row, "scope", "adopted") == "adopted" || continue
                ratio = row["residual"] / row["tolerance"]
                maxima[block] = max(maxima[block], ratio)
                failed += !row["pass"]
                push!(
                    residuals,
                    (
                        record = item["id"],
                        run_id = x.result["run_id"],
                        block = block,
                        formula = row["id"],
                        object = get(row, "entity", get(row, "object", "")),
                        step = get(row, "t", get(row, "step", 0)),
                        scenario = row["scenario"],
                        residual = row["residual"],
                        tolerance = row["tolerance"],
                        normalized_residual = ratio,
                        unit = row["unit"],
                        pass = row["pass"],
                    ),
                )
            end
        end
        candidate = haskey(q, "shared")
        push!(
            summaries,
            (
                record = item["id"],
                run_id = x.result["run_id"],
                status = x.result["status"],
                has_candidate = candidate,
                model_pass = q["model_pass"],
                shared_pass = candidate ? q["shared"]["shared_block_pass"] : missing,
                thermal_pass = candidate ? q["thermal"]["same_dispatch_pass"] : missing,
                max_shared_normalized = candidate ? maxima["shared"] : missing,
                max_thermal_normalized = candidate ? maxima["thermal"] : missing,
                failed_rows = candidate ? failed : missing,
                flow_residual_kg_s = get(q, "flow_schedule_residual_kg_s", missing),
                battery_mutual_exclusivity = candidate ? q["shared"]["mutual_exclusivity_pass"] :
                                             missing,
                simultaneous_charge_discharge_MW = candidate ?
                                                   q["shared"]["max_simultaneous_charge_discharge_MW"] :
                                                   missing,
            ),
        )
    end
    Dict("validation-summary.csv" => summaries, "residuals.csv" => residuals)
end

function transport_csv_bytes(rows)
    io = IOBuffer()
    CSV.write(io, rows; newline = '\n')
    take!(io)
end

function transport_audit(src, out; check = false)
    tables = transport_audit_tables(src)
    meta = Dict(
        "schema" => "r7-transport-audit-v1",
        "origin" => "synthetic",
        "solver_called" => false,
        "report_manifest_sha256" => bytes2hex(sha256(read(joinpath(src, "files.toml")))),
        "audit_source_sha256" => bytes2hex(sha256(read(@__FILE__))),
        "files" => Dict(k => bytes2hex(sha256(transport_csv_bytes(v))) for (k, v) in tables),
    )
    if check
        TOML.parsefile(joinpath(out, "audit.toml")) == meta || error("审计来源或哈希改变")
        Set(readdir(out)) == Set(vcat(collect(keys(tables)), ["audit.toml"])) ||
            error("审计文件集合改变")
        for (p, rows) in tables
            read(joinpath(out, p)) == transport_csv_bytes(rows) || error("审计残差与原值不符")
        end
    else
        ispath(out) && error("不覆盖既有审计")
        mkpath(out)
        for (p, rows) in tables
            write(joinpath(out, p), transport_csv_bytes(rows))
        end
        write(joinpath(out, "audit.toml"), PaperRebuild.r7_text(meta))
    end
    for r in tables["validation-summary.csv"]
        r.has_candidate && !r.model_pass || continue
        println(
            r.record,
            ": shared=",
            r.shared_pass,
            " thermal=",
            r.thermal_pass,
            " max_A1_ratio=",
            r.max_thermal_normalized,
            " failed_rows=",
            r.failed_rows,
        )
        bad = filter(x -> x.record == r.record && !x.pass, tables["residuals.csv"])
        for id in sort(unique(x.formula for x in bad))
            z = sort(
                filter(x -> x.formula == id, bad);
                by = x -> x.normalized_residual,
                rev = true,
            )[1]
            println(
                "  ",
                id,
                " ",
                z.object,
                " step=",
                z.step,
                " residual=",
                z.residual,
                " ",
                z.unit,
                " tolerance=",
                z.tolerance,
            )
        end
    end
    println(
        check ? "Saved transport audit independently checked." :
        "Transport residual audit saved without solving.",
    )
end

if abspath(PROGRAM_FILE) == @__FILE__
    length(ARGS) == 3 && ARGS[1] in ("create", "check") ||
        error("usage: audit_r7_transport.jl create|check REPORT AUDIT")
    transport_audit(abspath(ARGS[2]), abspath(ARGS[3]); check = ARGS[1] == "check")
end
