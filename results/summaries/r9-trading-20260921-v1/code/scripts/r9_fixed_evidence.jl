# 原字节去重封存及无求解器重验。科学失败与启动/检查器失败分别保留。
module R9FixedEvidence
using TOML, SHA, CSV, Dates, Test, JuMP
const MOI=JuMP.MOI
const ROOT=dirname(@__DIR__)
hashbytes(x) = bytes2hex(sha256(x))
toml(p, x) = open(io->TOML.print(io, x; sorted = true), p, "w")
function object(out, bytes)
    hash=hashbytes(bytes)
    if length(bytes)>4*1024^2
        chunkfile=joinpath(out, "object-chunks.toml")
        manifest=isfile(chunkfile) ? TOML.parsefile(chunkfile) :
                 Dict{String,Any}("objects"=>Dict{String,Any}())
        parts=[object(out, bytes[i:min(i+4*1024^2-1, end)]) for i in 1:(4*1024^2):length(bytes)]
        manifest["objects"][hash]=Dict("bytes"=>length(bytes), "parts"=>parts)
        toml(chunkfile, manifest)
        return hash
    end
    path=joinpath(out, "objects", hash)
    isfile(path) || write(path, bytes)
    hashbytes(read(path))==hash || error("Object changed")
    return hash
end
function bytes(out, hash)
    occursin(r"^[0-9a-f]{64}$", hash) || error("Invalid object hash")
    path=joinpath(out, "objects", hash)
    b=if isfile(path)
        read(path)
    else
        chunks=TOML.parsefile(joinpath(out, "object-chunks.toml"))["objects"][hash]
        joined=reduce(vcat, (bytes(out, h) for h in chunks["parts"]))
        length(joined)==chunks["bytes"] || error("Chunk length changed")
        joined
    end
    hashbytes(b)==hash || error("Object bytes changed")
    return b
end
parseobject(out, hash) = TOML.parse(String(bytes(out, hash)))
function pack(out, folder)
    files=Dict{String,String}()
    for (dir, _, names) in walkdir(folder), name in sort(names)
        path=joinpath(dir, name)
        relative=replace(relpath(path, folder), '\\'=>'/')
        files[relative]=object(out, read(path))
    end
    return files
end
function csvbytes(rows)
    io=IOBuffer()
    CSV.write(io, rows; newline = '\n')
    return take!(io)
end

# 逐式KKT表按固定行数分片；每片仍含表头，拒绝超过项目单文件限制。
function table_parts(name, rows)
    content=csvbytes(rows)
    length(content)<=4*1024^2 && return [string(name)*".csv"=>content]
    parts=[
        string(name)*"-"*lpad(string(k), 3, '0')*".csv" => csvbytes(rows[i:min(i+4999, end)]) for
        (k, i) in enumerate(1:5000:length(rows))
    ]
    all(length(last(p))<=4*1024^2 for p in parts) || error("Table shard is too large")
    return parts
end

# 根据冻结的原始乘子及约束矩阵重算KKT；不用求解器，不相信原trusted标志。
function replay_kkt(b, k, solver_status)
    haskey(k, "rows") || return Dict{String,Any}(
        "trusted"=>false,
        "available"=>false,
        "reason"=>get(k, "reason", "not_collected"),
    )
    duals=Dict(x["constraint"]=>x for x in k["rows"])
    point=Dict{VariableRef,Float64}()
    references=[
        cr for (F, S) in list_of_constraint_types(b.model) for cr in all_constraints(b.model, F, S)
    ]
    length(references)==length(duals) || error("KKT row set changed")
    for cr in references
        obj=constraint_object(cr)
        raw=duals[string(index(cr))]
        if obj.func isa VariableRef
            v=only(raw["primal"])
            haskey(point, obj.func) && point[obj.func]!=v && error("Variable witness inconsistent")
            point[obj.func]=v
        end
    end
    all(haskey(point, v) for v in all_variables(b.model)) || error("KKT primal variables missing")
    evaluate(x) = x isa Real ? Float64(x) : value(v->point[v], x)
    terms(x::Real) = Tuple{Float64,VariableRef}[]
    terms(x::VariableRef) = [(1.0, x)]
    terms(x::AffExpr) = collect(linear_terms(x))
    constantvalue(x::Real) = Float64(x)
    constantvalue(x::VariableRef) = 0.0
    constantvalue(x::AffExpr) = constant(x)
    objective=objective_function(b.model)
    objective isa Union{VariableRef,AffExpr} || error("Unexpected fixed-flow objective")
    station=Dict(v=>0.0 for v in all_variables(b.model))
    for (a, v) in terms(objective)
        station[v]+=a
    end
    denom=Dict(v=>1+abs(x) for (v, x) in station)
    nrm(x) = sqrt(sum(abs2, x))
    primal, dualerr, complement=0.0, 0.0, 0.0
    dualobjective=constantvalue(objective)
    rows=NamedTuple[]
    for cr in references
        obj=constraint_object(cr)
        f, set=obj.func, obj.set
        raw=duals[string(index(cr))]
        fs=f isa AbstractVector ? f : [f]
        val=evaluate.(fs)
        y=raw["raw_dual"]
        length(val)==length(y) || error("Dual dimension changed")
        maximum(abs.(val-raw["primal"]); init = 0.0)<=1e-9 ||
            error("KKT primal expression mismatch")
        rhs=zeros(length(fs))
        if set isa MOI.EqualTo
            rhs[1]=set.value
            slack=val-rhs
            pe, de=abs(only(slack)), 0.0
        elseif set isa MOI.LessThan
            rhs[1]=set.upper
            slack=val-rhs
            pe, de=max(0.0, only(slack)), max(0.0, only(y))
        elseif set isa MOI.GreaterThan
            rhs[1]=set.lower
            slack=val-rhs
            pe, de=max(0.0, -only(slack)), max(0.0, -only(y))
        elseif set isa MOI.SecondOrderCone
            slack=val
            pe, de=max(0.0, nrm(val[2:end])-val[1]), max(0.0, nrm(y[2:end])-y[1])
        else
            error("Unsupported frozen KKT constraint")
        end
        for (i, expression) in enumerate(fs)
            dualobjective-=y[i]*(constantvalue(expression)-rhs[i])
            for (a, v) in terms(expression)
                station[v]-=y[i]*a
                denom[v]+=abs(y[i]*a)
            end
        end
        pe/=max(1, nrm(val), nrm(slack))
        de/=max(1, nrm(y))
        ce=abs(sum(slack .* y))/max(1, nrm(slack)*nrm(y))
        primal, dualerr, complement=max(primal, pe), max(dualerr, de), max(complement, ce)
        push!(
            rows,
            (;
                constraint = string(index(cr)),
                set = string(typeof(set)),
                primal_error = pe,
                dual_error = de,
                complementarity = ce,
            ),
        )
    end
    st=maximum(abs(station[v])/denom[v] for v in keys(station); init = 0.0)
    cost=evaluate(objective)
    gap=abs(cost-dualobjective)/max(1, abs(cost))
    trusted=solver_status=="OPTIMAL" && max(primal, dualerr, complement, st)<=1e-6 && gap<=1e-4
    return Dict{String,Any}(
        "available"=>true,
        "trusted"=>trusted,
        "primal"=>primal,
        "dual"=>dualerr,
        "complementarity"=>complement,
        "stationarity"=>st,
        "relative_gap"=>gap,
        "dual_objective_CNY"=>dualobjective,
        "rows"=>rows,
    )
end

function replay(out, index)
    for (_, payload) in index["diagnostics"]
        for name in ("manifest.toml", "audit.toml")
            haskey(payload, name) || continue
            metadata=parseobject(out, payload[name])
            for section in ("files", "output_files"), (path, hash) in get(metadata, section, Dict())
                @test payload[path]==hash
            end
        end
    end
    formal=index["formal"]
    manifest=parseobject(out, formal["manifest.toml"])
    @test manifest["schema"]=="r9-fixed-study-v1"
    @test !manifest["uses_projected_gradient"] && !manifest["initial_primal_injection"]
    @test manifest["gurobi_presolve"]==0
    @test Set((e["terminal"], e["solver"]) for e in manifest["entries"]) ==
          Set((t, s) for t in ("literal", "roundoff_band") for s in ("Clarabel", "Gurobi"))
    for (path, hash) in manifest["files"]
        @test formal[path]==hash
        bytes(out, hash)
    end
    mod=Module(gensym(:R9FixedReplay))
    Core.eval(mod, :(using JuMP, TOML, SHA, Dates, UUIDs, CSV, Random))
    for path in manifest["science_files"]
        Base.include(mod, joinpath(out, "objects", formal["code/"*path]))
    end
    return Base.invokelatest() do
        c=getfield(mod, :load_r9_pv_case)(joinpath(out, "objects", formal["case.toml"]))
        parent=parseobject(out, formal["vf-vt-parent.toml"])
        expectedflow=getfield(mod, :r2_flow_hash)(
            getfield(mod, :r2_flow_matrix)(c, parent["values"]["m_pipe"]),
        )
        summary, ratios, trajectories, kktrows=NamedTuple[],
        NamedTuple[],
        NamedTuple[],
        NamedTuple[]
        for e in manifest["entries"]
            id=e["id"]
            resultpath="runs/"*id*"/result.toml"
            receipt=parseobject(out, formal["runs/"*id*"/receipt.toml"])
            @test receipt["entry"]==e
            @test receipt["result_sha256"]==formal[resultpath]
            r=parseobject(out, formal[resultpath])
            r["status"]=="exception" &&
                error("Execution exception requires explicit report handling")
            @test r["mode"]==e["mode"] && r["terminal_interpretation"]==e["terminal"]
            @test r["input_sha256"]==c.sha256 && r["flow_sha256"]==expectedflow
            @test !r["uses_projected_gradient"] && !r["physical_model"]
            v=getfield(mod, :validate_r9_fixed_solution)(c, r)
            for key in (
                :model_pass,
                :physical_pass,
                :terminal_pass,
                :daily_energy_pass,
                :representation_pass,
            )
                @test r["validation"][string(key)]==getproperty(v, key)
            end
            b=getfield(mod, :build_r9_reduced_model)(
                c;
                mode = Symbol(e["mode"]),
                flow_schedule = r["flow_schedule"],
                terminal = Symbol(e["terminal"]),
            )
            s, k=r["stage"], r["kkt"]
            kr=replay_kkt(b, k, get(s, "termination", "missing"))
            if kr["available"]
                for key in ("primal", "dual", "complementarity", "stationarity")
                    @test isapprox(kr[key], k[key]; atol = 1e-10, rtol = 1e-8)
                end
                for row in kr["rows"]
                    push!(kktrows, merge((; run_id = id), row))
                end
            end
            push!(
                summary,
                (;
                    run_id = id,
                    terminal = e["terminal"],
                    solver = e["solver"],
                    status = r["status"],
                    model_pass = v.model_pass,
                    physical_pass = v.physical_pass,
                    terminal_pass = v.terminal_pass,
                    representation_pass = v.representation_pass,
                    daily_energy_pass = v.daily_energy_pass,
                    kkt_collected = kr["available"],
                    kkt_trusted = kr["trusted"],
                    kkt_reported_trusted = k["trusted"],
                    kkt_complementarity = get(kr, "complementarity", NaN),
                    kkt_relative_gap = get(kr, "relative_gap", NaN),
                    cost_CNY = get(s, "operating_cost", NaN),
                    bound_CNY = get(s, "solver_bound", NaN),
                    elapsed_sec = receipt["wall_sec"],
                    budget_pass = r["wall_budget_pass"]&&receipt["wall_sec"]<=600,
                ),
            )
            for (scope, predicate) in (
                ("model", x->x.scope=="model"),
                ("physical", x->x.scope=="physics"),
                ("adopted_terminal", x->x.equation=="R9-F3-adopted-terminal"),
                (
                    "periodic",
                    x->startswith(x.equation, "R9-V4") || x.equation=="R9-P6-terminal-memory",
                ),
            )
                rs=filter(predicate, v.rows)
                scope in ("model", "physical", "periodic") && @test !isempty(rs)
                scope=="physical" && @test length(rs)==9096
                scope=="periodic" && @test length(rs)==111
                push!(
                    ratios,
                    (;
                        run_id = id,
                        scope,
                        rows = length(rs),
                        failures = count(x->!x.pass, rs),
                        max_ratio = maximum(x.residual/x.tolerance for x in rs; init = 0.0),
                    ),
                )
            end
            if haskey(s, "values")
                for (j, n) in enumerate(c.data["heat"]["nodes"]), t in 1:c.data["T"]
                    n["role"]=="source" || continue
                    push!(
                        trajectories,
                        (;
                            run_id = id,
                            node = j,
                            t,
                            source_temperature_K = s["values"]["tau_S_port"][j][t],
                            heat_MW = s["values"]["H_port"][j][t],
                        ),
                    )
                end
            end
        end
        m=getfield(mod, :r2_flow_matrix)(c, parent["values"]["m_pipe"])
        diagnostic=getfield(mod, :build_r9_reduced_model)(
            c;
            mode = :VF_VT,
            flow_schedule = m,
            terminal = :rank_checked_rhs,
        )
        cert=diagnostic.terminal_certificate
        U=permutedims(hcat(cert["basis"]...))
        source=[
            parent["values"]["tau_S_port"][j][t]-diagnostic.temperature_centre_K for
            (j, t) in cert["source_coordinates"]
        ]
        change=maximum(abs, cert["offset_K"]+U*(U'*(source-cert["offset_K"]))-source)
        @test change≈16.441653850438172 atol=1e-6
        @test cert["rank_exact_binary"]==32 && cert["free_source_count"]==16
        @test maximum(cert["row_error_bound_K"])<=1e-10
        diagnostics=[
            (; metric = "source_projection_max_change", value = change, unit = "K"),
            (; metric = "rank_exact_binary", value = 32.0, unit = "1"),
            (; metric = "kernel_dimension", value = 16.0, unit = "1"),
            (;
                metric = "max_terminal_representation_bound",
                value = maximum(cert["row_error_bound_K"]),
                unit = "K",
            ),
        ]
        return (; summary, ratios, trajectories, kktrows, diagnostics)
    end
end

function freeze(study, out)
    ispath(out) && error("Do not overwrite evidence")
    mkpath(joinpath(out, "objects"))
    formal=pack(out, study)
    diagnostics=Dict{String,Any}()
    for name in (
        "r9-fixed-witness-20260921-v1",
        "r9-fixed-scaling-20260921-v1",
        "r9-fixed-scaling-review-20260921-v1",
        "r9-fixed-terminal-20260921-v1",
        "r9-fixed-terminal-exact-20260921-v1",
        "r9-fixed-study-20260921-v1",
    )
        diagnostics[name]=pack(out, joinpath(ROOT, "results/runs", name))
    end
    logs=Dict{String,String}()
    for name in (
        "r9-fixed-tests-v1.log",
        "r9-fixed-tests-v2.log",
        "r9-fixed-tests-v3.log",
        "r9-fixed-tests-v4.log",
        "r9-fixed-clarabel-v1.log",
    )
        raw=read(joinpath(ROOT, "tmp", name), String)
        public=replace(raw, ROOT=>"<workspace>", get(ENV, "USERPROFILE", "<none>")=>"<user>")
        logs[name]=object(out, codeunits(public))
    end
    index=Dict(
        "schema"=>"r9-fixed-evidence-v2",
        "origin"=>"synthetic",
        "formal"=>formal,
        "diagnostics"=>diagnostics,
        "development_logs"=>logs,
        "audit_source"=>object(out, read(@__FILE__)),
        "created_utc"=>string(now(UTC)),
    )
    toml(joinpath(out, "index.toml"), index)
    tables=Ref{Any}()
    @testset "R9 fixed frozen original values and independent KKT" begin
        tables[]=replay(out, index)
    end
    for (name, rows) in pairs(tables[]), (file, content) in table_parts(name, rows)
        write(joinpath(out, file), content)
    end
    files=Dict(
        p=>hashbytes(read(joinpath(out, p))) for p in readdir(out) if isfile(joinpath(out, p))
    )
    toml(joinpath(out, "artifact-hashes.toml"), Dict("files"=>files))
    println("Frozen R9 fixed-flow evidence; no scientific rerun.")
end

function check(out)
    @testset "R9 fixed evidence hashes, original values and KKT" begin
        for (p, h) in TOML.parsefile(joinpath(out, "artifact-hashes.toml"))["files"]
            @test hashbytes(read(joinpath(out, p)))==h
        end
        index=TOML.parsefile(joinpath(out, "index.toml"))
        @test index["schema"] in ("r9-fixed-evidence-v1", "r9-fixed-evidence-v2") &&
              index["origin"]=="synthetic"
        for h in readdir(joinpath(out, "objects"))
            bytes(out, h)
        end
        data=replay(out, index)
        for (name, rows) in pairs(data), (file, content) in table_parts(name, rows)
            @test read(joinpath(out, file))==content
        end
    end
end
function main(args)
    length(args)==3 && args[1]=="freeze" && return freeze(abspath(args[2]), abspath(args[3]))
    length(args)==2 && args[1]=="check" && return check(abspath(args[2]))
    error("usage: r9_fixed_evidence.jl freeze STUDY NEW_ARCHIVE | check ARCHIVE")
end
end
if abspath(PROGRAM_FILE)==abspath(@__FILE__)
    R9FixedEvidence.main(ARGS)
end
