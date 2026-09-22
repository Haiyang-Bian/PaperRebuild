# 内容寻址封存：重复源码只存一次；原记录不改写。重验不加载求解器。
using TOML, SHA, CSV, Dates, Test
const r9fe_root = dirname(@__DIR__)
r9fe_hash(bytes) = bytes2hex(sha256(bytes))
r9fe_toml(p, x) = open(io->TOML.print(io, x; sorted = true), p, "w")
function r9fe_object(out, bytes)
    hash=r9fe_hash(bytes)
    path=joinpath(out, "objects", hash)
    isfile(path) || write(path, bytes)
    r9fe_hash(read(path))==hash || error("Object hash mismatch")
    return hash
end
function r9fe_bytes(out, hash)
    occursin(r"^[0-9a-f]{64}$", hash) || error("Invalid object ID")
    bytes=read(joinpath(out, "objects", hash))
    r9fe_hash(bytes)==hash || error("Tampered object")
    return bytes
end
r9fe_parse(out, hash) = TOML.parse(String(r9fe_bytes(out, hash)))
function r9fe_csv(rows)
    io=IOBuffer()
    CSV.write(io, rows; newline = '\n')
    return String(take!(io))
end

function r9fe_freeze(study, out)
    ispath(out) && error("Do not overwrite evidence")
    master=TOML.parsefile(joinpath(study, "manifest.toml"))
    protocol=TOML.parsefile(joinpath(study, "protocol.toml"))
    protocol["modes"]==["CF_CT", "CF_VT", "VF_CT", "VF_VT"] || error("Protocol changed")
    mkpath(joinpath(out, "objects"))
    code=Dict{String,String}()
    for (path, hash) in master["files"]
        bytes=read(joinpath(study, "frozen", path))
        r9fe_hash(bytes)==hash || error("Study frozen source changed")
        code[path]=r9fe_object(out, bytes)
    end
    entries=Dict{String,Any}[]
    records=[
        (lowercase(m), "formal", joinpath(study, "runs", lowercase(m))) for m in protocol["modes"]
    ]
    for suffix in (
        "local-cost-v1",
        "local-complementarity-v1",
        "terminal-free-v1",
        "terminal-fix-v1",
        "presolve-off-v1",
    )
        id="r9-flow-probe-vf-vt-"*suffix
        push!(records, (id, "development", joinpath(r9fe_root, "tmp", id)))
    end
    for (id, group, folder) in records
        manifest=TOML.parsefile(joinpath(folder, "manifest.toml"))
        payload=Dict{String,String}()
        for (path, hash) in manifest["files"]
            isabspath(path) || ".." in split(replace(path, '\\'=>'/'), '/') ? error("Unsafe path") :
            nothing
            bytes=read(joinpath(folder, path))
            r9fe_hash(bytes)==hash || error("Probe source changed")
            payload[path]=r9fe_object(out, bytes)
        end
        for name in (
            "manifest.toml",
            "stage.toml",
            "evidence.toml",
            "native-start-audit.toml",
            "implied-cones.toml",
            "native-iterations.csv",
            "initial-raw-residuals.csv",
            "residuals.csv",
            "memory-balance.csv",
            "objective-scale.toml",
            "terminal-fixing.toml",
            "terminal-removal.toml",
        )
            path=joinpath(folder, name)
            isfile(path) && (payload[name]=r9fe_object(out, read(path)))
        end
        group=="formal" && (
            payload["execution.toml"]=r9fe_object(out, read(joinpath(study, id*"-execution.toml")))
        )
        raw=read(joinpath(folder, "solver-local.log"), String)
        public=replace(raw, r9fe_root=>"<workspace>", replace(r9fe_root, '\\'=>'/')=>"<workspace>")
        public=replace(
            public,
            r"(?m)^.*(?:LicenseID|Academic license|Set parameter Username).*$"=>"[local license metadata omitted]",
        )
        payload["solver-local.log"]=r9fe_object(out, codeunits(public))
        push!(
            entries,
            Dict(
                "id"=>id,
                "group"=>group,
                "payload"=>payload,
                "original_solver_log_sha256"=>r9fe_hash(codeunits(raw)),
                "log_transformation"=>"workspace paths and license metadata redacted only",
            ),
        )
    end
    index=Dict(
        "schema"=>"r9-flow-reference-evidence-v1",
        "origin"=>"synthetic",
        "code"=>code,
        "science_files"=>master["science_files"],
        "runs"=>entries,
        "protocol"=>protocol,
        "case"=>r9fe_object(out, read(joinpath(study, "case.toml"))),
        "study_manifest"=>r9fe_object(out, read(joinpath(study, "manifest.toml"))),
        "audit_script"=>r9fe_object(out, read(@__FILE__)),
        "created_utc"=>string(now(UTC)),
    )
    r9fe_toml(joinpath(out, "index.toml"), index)
    tables=r9fe_replay(out, index)
    for (name, rows) in pairs(tables)
        write(joinpath(out, string(name)*".csv"), r9fe_csv(rows))
    end
    files=Dict(
        p=>r9fe_hash(read(joinpath(out, p))) for p in readdir(out) if isfile(joinpath(out, p))
    )
    r9fe_toml(joinpath(out, "artifact-hashes.toml"), Dict("files"=>files))
    r9fe_check(out)
end

function r9fe_replay(out, index)
    mod=Module(gensym(:R9Readback))
    Core.eval(mod, :(using JuMP, TOML, SHA, Dates, UUIDs, CSV, Random))
    for path in index["science_files"]
        r9fe_bytes(out, index["code"][path])
        Base.include(mod, joinpath(out, "objects", index["code"][path]))
    end
    return Base.invokelatest() do
        c=getfield(mod, :load_r9_pv_case)(joinpath(out, "objects", index["case"]))
        c.sha256==index["protocol"]["input_sha256"] || error("Case identity mismatch")
        summary, ratios, memory, trajectories, iterations = (NamedTuple[] for _ in 1:5)
        for entry in index["runs"]
            id, payload=entry["id"], entry["payload"]
            manifest=r9fe_parse(out, payload["manifest.toml"])
            for (path, hash) in manifest["files"]
                @test payload[path]==hash
                r9fe_bytes(out, hash)
            end
            @test payload["case.toml"]==index["case"]
            @test !manifest["uses_projected_gradient"]
            s=r9fe_parse(out, payload["stage.toml"])
            e=r9fe_parse(out, payload["evidence.toml"])
            v=getfield(mod, :validate_r3_solution)(c, s)
            terminal=getfield(mod, :r9_flow_terminal_rows)(c, s)
            candidate=haskey(s, "values")
            terminal_pass=candidate && all(r.pass for r in terminal)
            rows=vcat(v.rows, terminal)
            for scope in ("model", "physics"),
                formula in sort(unique(r.equation for r in rows if r.scope==scope))

                rs=[r for r in rows if r.equation==formula && r.scope==scope]
                push!(
                    ratios,
                    (;
                        run_id = id,
                        scope,
                        formula,
                        max_ratio = maximum(r.residual/r.tolerance for r in rs),
                        failed = count(!r.pass for r in rs),
                        count = length(rs),
                    ),
                )
            end
            @test v.model_pass==e["model_pass"]
            @test v.physical_pass==e["physical_pass"]
            @test terminal_pass==e["terminal_pass"]
            cost=source=loss=delta=pv=flow_deviation=energy_ratio=NaN
            energy_pass=false
            if candidate
                cost=getfield(mod, :r3_operating_cost)(c, s["values"])
                @test isapprox(cost, s["operating_cost"]; atol = 1e-6, rtol = 0)
                a=getfield(mod, :r9_heat_memory_balance)(c, s["values"])
                heat=getfield(mod, :r9_daily_heat_balance)(c, s["values"])
                source, loss, delta=heat.source_MWh, a.attenuation_MWh, a.memory_change_MWh
                energy_ratio=heat.residual_MWh/heat.tolerance_MWh
                energy_pass=heat.pass
                @test abs(a.residual_MWh)<=1e-10
                @test abs(a.net_MWh-heat.pipe_net_MWh)<=1e-10
                append!(memory, [merge((; run_id = id), r) for r in a.rows])
                d, values=c.data, s["values"]
                pv=d["dt_h"]*sum(
                    sum(values["P_device"][i]) for
                    (i, g) in enumerate(d["devices"]) if g["kind"]=="PV"
                )
                flow_deviation=maximum(
                    abs(values["m_pipe"][p][t]/first(pipe["fixed_flow"])-1) for
                    (p, pipe) in enumerate(d["heat"]["pipes"]), t in 1:d["T"]
                )
                for t in 1:d["T"]
                    source_nodes=[
                        j for (j, n) in enumerate(d["heat"]["nodes"]) if n["role"]=="source"
                    ]
                    push!(
                        trajectories,
                        (;
                            run_id = id,
                            t,
                            flow_1_kg_s = values["m_pipe"][1][t],
                            source_1_K = values["tau_S_port"][source_nodes[1]][t],
                            source_2_K = values["tau_S_port"][source_nodes[2]][t],
                            source_heat_MW = sum(values["H_port"][j][t] for j in source_nodes),
                            grid_MW = values["P_grid"][t],
                            pv_MW = sum(
                                values["P_device"][i][t] for
                                (i, g) in enumerate(d["devices"]) if g["kind"]=="PV"
                            ),
                        ),
                    )
                end
            end
            if haskey(payload, "native-iterations.csv")
                for row in CSV.File(IOBuffer(r9fe_bytes(out, payload["native-iterations.csv"])))
                    push!(
                        iterations,
                        (;
                            run_id = id,
                            iteration = row.iteration,
                            objective = row.objective,
                            primal = row.primal,
                            dual = row.dual,
                            complementarity = row.complementarity,
                        ),
                    )
                end
            end
            full=v.physical_pass && terminal_pass && energy_pass
            eligible=entry["group"]=="formal" && full
            wall=haskey(payload, "execution.toml") ?
                 r9fe_parse(out, payload["execution.toml"])["wall_sec_including_imports"] :
                 e["elapsed_sec"]
            push!(
                summary,
                (;
                    run_id = id,
                    group = entry["group"],
                    mode = manifest["mode"],
                    termination = s["termination"],
                    primal = s["primal"],
                    candidate,
                    model_pass = v.model_pass,
                    physical_pass = v.physical_pass,
                    terminal_pass,
                    energy_pass,
                    full_accepted = full,
                    periodic_comparison_eligible = eligible,
                    cost_CNY = cost,
                    source_MWh = source,
                    attenuation_MWh = loss,
                    memory_change_MWh = delta,
                    pv_MWh = pv,
                    max_relative_flow_change = flow_deviation,
                    energy_ratio,
                    elapsed_sec = e["elapsed_sec"],
                    wall_sec = wall,
                    budget_sec = manifest["budget_sec"],
                    budget_pass = e["budget_pass"]&&wall<=manifest["budget_sec"],
                    global_bound_available = haskey(s, "solver_bound"),
                ),
            )
        end
        return (; summary, ratios, memory, trajectories, iterations)
    end
end

function r9fe_check(out)
    @testset "R9 frozen flow-reference and terminal diagnosis" begin
        meta=TOML.parsefile(joinpath(out, "artifact-hashes.toml"))
        for (path, hash) in meta["files"]
            !isabspath(path) && dirname(path) in ("", ".") || error("Unsafe artifact name")
            @test basename(path) == path
            @test r9fe_hash(read(joinpath(out, path)))==hash
        end
        index=TOML.parsefile(joinpath(out, "index.toml"))
        @test index["schema"]=="r9-flow-reference-evidence-v1"
        @test length(index["runs"])==9
        @test count(e["group"]=="formal" for e in index["runs"])==4
        for hash in readdir(joinpath(out, "objects"))
            @test r9fe_hash(r9fe_bytes(out, hash))==hash
        end
        for (name, rows) in pairs(r9fe_replay(out, index))
            @test r9fe_csv(rows)==read(joinpath(out, string(name)*".csv"), String)
        end
    end
end

if abspath(PROGRAM_FILE)==@__FILE__
    if length(ARGS)==3 && ARGS[1]=="freeze"
        r9fe_freeze(abspath(ARGS[2]), abspath(ARGS[3]))
    elseif length(ARGS)==2 && ARGS[1]=="check"
        r9fe_check(abspath(ARGS[2]))
    else
        error("usage: r9_flow_evidence.jl freeze STUDY NEW_REPORT | check REPORT")
    end
end
