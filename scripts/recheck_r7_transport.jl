using CSV, TOML, SHA
include("r7_transport_study.jl")

"""使用固定流量契约的正确分支复核原值，分别保存历史判定与补证，不调用优化器。"""
function transport_recheck_tables(src, api)
    transport_manifest(src) == TOML.parsefile(joinpath(src, "files.toml"))["files"] ||
        error("原报告改变")
    input, _ = transport_inputs(src)
    summary = NamedTuple[]
    branch = NamedTuple[]
    output = Dict{String,Vector{UInt8}}()
    for item in input["records"]
        path = joinpath(src, "records", item["id"])
        old = transport_read(path)
        c = Base.invokelatest(getfield(api, :R7RecoveryCase), old.case.data)
        q = Base.invokelatest(
            getfield(api, :validate_r7_transport_recovery),
            c,
            old.spec,
            old.result,
        )
        r = old.result
        candidate = haskey(r, "values")
        push!(
            summary,
            (
                record = item["id"],
                run_id = r["run_id"],
                status = r["status"],
                original_model_pass = old.validation["model_pass"],
                corrected_model_pass = q["model_pass"],
                conditional_optimality = q["conditional_optimality_pass"],
                old_max_thermal_normalized = candidate ?
                                             old.validation["thermal"]["max_normalized_residual"] :
                                             missing,
                new_max_thermal_normalized = candidate ? q["thermal"]["max_normalized_residual"] :
                                             missing,
                flow_residual_kg_s = get(q, "flow_schedule_residual_kg_s", missing),
                battery_mutual_exclusivity = candidate ? q["shared"]["mutual_exclusivity_pass"] :
                                             missing,
                simultaneous_charge_discharge_MW = candidate ?
                                                   q["shared"]["max_simultaneous_charge_discharge_MW"] :
                                                   missing,
                loss_MWh = get(q, "loss_MWh", missing),
            ),
        )
        if candidate
            for name in ("m_source", "m_load", "m_pipe")
                declared = PaperRebuild.r7_unpack(old.spec["flow_schedule"], name)
                raw = PaperRebuild.r7_unpack(r["values"], name)
                for i in CartesianIndices(declared)
                    declared[i] == 0 && raw[i] != 0 || continue
                    push!(
                        branch,
                        (
                            record = item["id"],
                            run_id = r["run_id"],
                            variable = name,
                            entity = i[1],
                            time = i[2],
                            declared_kg_s = declared[i],
                            raw_kg_s = raw[i],
                            original_positive_branch = raw[i] > 0,
                            declared_positive_branch = false,
                        ),
                    )
                end
            end
        end
        record = Dict(
            "original_result_sha256" => bytes2hex(sha256(read(joinpath(path, "result.toml")))),
            "run_id" => r["run_id"],
            "original_model_pass" => old.validation["model_pass"],
            "solver_called" => false,
            "validation" => q,
        )
        output["records/"*item["id"]*".toml"] = collect(codeunits(PaperRebuild.r7_text(record)))
    end
    for (p, table) in (("summary.csv", summary), ("zero-branch.csv", branch))
        io = IOBuffer()
        CSV.write(io, table; newline = '\n')
        output[p] = take!(io)
    end
    output
end

function recheck_r7_transport(src, out; check = false)
    if check
        transport_manifest(out) == TOML.parsefile(joinpath(out, "files.toml"))["files"] ||
            error("补证文件改变")
        metadata = TOML.parsefile(joinpath(out, "recheck.toml"))
        metadata["original_report_sha256"] ==
        bytes2hex(sha256(read(joinpath(src, "files.toml")))) || error("原证据身份改变")
        metadata["script_sha256"] == bytes2hex(sha256(read(@__FILE__))) || error("补证入口改变")
        wrapper = Module(gensym(:TransportCorrection))
        Base.include(wrapper, joinpath(out, "code/replay.jl"))
        api = Base.invokelatest(getfield, wrapper, :FrozenTransportCorrection)
        hashes = Base.invokelatest(getfield(api, :r7_transport_science_hashes))
        hashes == metadata["science"] || error("补证冻结源码不符")
        for (p, b) in transport_recheck_tables(src, api)
            read(joinpath(out, p)) == b || error("补证与保存原值不符")
        end
    else
        ispath(out) && error("不覆盖补证")
        output = transport_recheck_tables(src, PaperRebuild)
        for (p, b) in output
            path = joinpath(out, p)
            mkpath(dirname(path))
            write(path, b)
        end
        for (p, f) in PaperRebuild.r7_transport_science_paths()
            path = joinpath(out, "code", p)
            mkpath(dirname(path))
            cp(f, path)
        end
        layers = ("core", "formulations", "verification", "algorithms", "reporting")
        code =
            "module FrozenTransportCorrection\nusing JuMP,TOML,SHA,Dates,UUIDs\nconst MOI=JuMP.MOI\n" *
            join("include(\"src/$layer/r7_recovery.jl\")\n" for layer in layers) *
            "include(\"src/networks/r7_pipe_state.jl\")\n" *
            join("include(\"src/$layer/r7_thermal.jl\")\n" for layer in layers) *
            join("include(\"src/$layer/r7_transport.jl\")\n" for layer in layers) *
            "end\n"
        write(joinpath(out, "code/replay.jl"), code)
        meta = Dict(
            "schema" => "r7-transport-recheck-v1",
            "origin" => "synthetic",
            "solver_called" => false,
            "reason" => "fixed-flow thermal coefficients and idle-port branches are defined by declared schedule; raw equality residual independently checked; no raw values clipped",
            "original_report_sha256" => bytes2hex(sha256(read(joinpath(src, "files.toml")))),
            "script_sha256" => bytes2hex(sha256(read(@__FILE__))),
            "science" => PaperRebuild.r7_transport_science_hashes(),
        )
        write(joinpath(out, "recheck.toml"), PaperRebuild.r7_text(meta))
        write(
            joinpath(out, "files.toml"),
            PaperRebuild.r7_text(Dict("files" => transport_manifest(out))),
        )
    end
    println(
        check ?
        "Original numeric values and frozen correction checked; historical status retained." :
        "Correction evidence saved without repeated optimization or changed numerical values.",
    )
end

if abspath(PROGRAM_FILE) == @__FILE__
    length(ARGS) == 3 && ARGS[1] in ("create", "check") ||
        error("usage: recheck_r7_transport.jl create|check REPORT RECHECK")
    recheck_r7_transport(abspath(ARGS[2]), abspath(ARGS[3]); check = ARGS[1] == "check")
end
