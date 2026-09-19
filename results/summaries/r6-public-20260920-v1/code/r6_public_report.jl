using PaperRebuild, CSV, TOML, SHA, Tar
include("r6_study_tables.jl")

r6_public_hash(path) = bytes2hex(sha256(read(path)))
r6_public_text(x) = sprint(io -> TOML.print(io, x; sorted = true))
function r6_public_path(root, rel)
    !isempty(rel) &&
    !isabspath(rel) &&
    !occursin(':', rel) &&
    !occursin('\\', rel) &&
    all(x -> !(x in ("", ".", "..")), split(rel, '/')) || error("非规范证据路径")
    joinpath(root, split(rel, '/')...)
end
function r6_public_inventory(root)
    out = Dict{String,String}()
    for (dir, dirs, files) in walkdir(root)
        any(islink(joinpath(dir, x)) for x in vcat(dirs, files)) && error("证据包不能含链接")
        for f in files
            p = joinpath(dir, f)
            out[replace(relpath(p, root), '\\' => '/')] = r6_public_hash(p)
        end
    end
    out
end
function r6_public_manifest(root)
    m = TOML.parsefile(joinpath(root, "public.toml"))
    r6_public_hash(joinpath(root, "public.toml")) ==
    strip(read(joinpath(root, "public.sha256"), String)) || error("证据清单改变")
    m["schema"] == "r6-public-evidence-v1" &&
    m["origin"] == "synthetic" &&
    m["test_physics_replayed_by_bundle"] === false &&
    m["stress_physics_replayed_by_bundle"] === true &&
    m["solver_reexecuted"] === false || error("证据范围改变")
    actual = r6_public_inventory(root)
    pop!(actual, "public.toml")
    pop!(actual, "public.sha256")
    actual == m["files"] || error("证据包缺失、额外文件或原值哈希改变")
    foreach(p -> r6_public_path(root, p), keys(actual))
    m
end

# 只从保存的PCC、室温和设备原值提取轨迹，保留全部四个压力日及全部六方法。
function r6_public_stress_tables(root)
    selection = TOML.parsefile(joinpath(root, "selection.toml"))["selected"]
    protocol = TOML.parsefile(joinpath(root, "protocol.toml"))
    freeze = TOML.parsefile(joinpath(root, "freeze.toml"))
    hourly, temperatures, devices = NamedTuple[], NamedTuple[], NamedTuple[]
    for chosen in selection
        id, method = chosen["candidate_id"], chosen["method"]
        p = TOML.parsefile(joinpath(root, "policies", id*".toml"))
        d, award = p["physical"]["dispatch"], p["award"]
        for day in freeze["spec"]["stress_cases"]
            r = TOML.parsefile(joinpath(root, "stress", id, "days", day*".toml"))["result"]
            y = r["stage"]["flat_values"]
            cumulative = 0.0
            for t in 1:d["T"]
                up = endswith(day, "_up")
                fraction =
                    startswith(day, "clear_") ? protocol["generator"]["clear_sky_fraction"][t] : 0.0
                request = up ? award["R_up_MW"][t] : -award["R_down_MW"][t]
                delivered = award["P_DA_MW"][t] - y["P_PCC/1/$t"]
                mismatch = abs(request - delivered)
                cumulative += d["dt_h"] * mismatch
                shared = (;
                    candidate = id,
                    method,
                    day_id = day,
                    run_id = r["run_id"],
                    t,
                    time_end_h = t*d["dt_h"],
                    dt_h = d["dt_h"],
                    trained_label = r["label"]["label"],
                    representative = r["label"]["scenario_id"],
                )
                push!(
                    hourly,
                    (;
                        shared...,
                        pv_fraction = fraction,
                        requested_MW = request,
                        delivered_MW = delivered,
                        mismatch_MW = mismatch,
                        cumulative_mismatch_MWh = cumulative,
                        P_PCC_MW = y["P_PCC/1/$t"],
                    ),
                )
                for (j, b) in enumerate(d["buildings"])
                    temp = y["τ_IN/$j/$t"]
                    # 只表示建筑相对初温的热状态，不能冒充电池或全管网储热量。
                    push!(
                        temperatures,
                        (;
                            shared...,
                            building = b["id"],
                            indoor_K = temp,
                            comfort_min_K = b["T_min_K"],
                            comfort_max_K = b["T_max_K"],
                            building_relative_heat_MWh = b["C_MWh_K"]*(temp-b["T_initial_K"]),
                            district_heat_MW = y["H_D/$j/$t"],
                            local_electric_heat_MW = b["COP_DH"]*y["P_DH/$j/$t"],
                            supply_K = y["τ_S/$(b["heat_node"])/$t"],
                            return_K = y["τ_load_R/$j/$t"],
                        ),
                    )
                end
                for (g, device) in enumerate(d["devices"])
                    push!(
                        devices,
                        (;
                            shared...,
                            device = device["id"],
                            kind = device["kind"],
                            P_MW = y["P_DER/$g/$t"],
                            Q_Mvar = y["Q_DER/$g/$t"],
                        ),
                    )
                end
            end
        end
    end
    r6_study_table_bytes(Dict("hourly"=>hourly, "temperatures"=>temperatures, "devices"=>devices))
end

"""导出R6已验算报告及24个压力日原值。随机日保留统计源表，未复制其全部物理原值。"""
function create_r6_public(source, report, output)
    ispath(output) && error("不能覆盖已存在的公开证据包")
    meta = TOML.parsefile(joinpath(report, "report.toml"))
    r6_public_hash(joinpath(report, "report.toml")) ==
    strip(read(joinpath(report, "report.sha256"), String)) || error("报告哈希错误")
    meta["complete"] === true && meta["origin"] == "synthetic" || error("需要完整的原值报告")
    meta["counts"] == Dict("training"=>14, "validation"=>14, "test"=>6, "stress"=>6) ||
        error("原报告数量错误")
    files = Dict{String,Vector{UInt8}}()
    for rel in vcat(collect(keys(meta["tables"])), ["report.toml", "report.sha256"])
        bytes = read(r6_public_path(report, rel))
        haskey(meta["tables"], rel) &&
            bytes2hex(sha256(bytes)) != meta["tables"][rel] &&
            error("源表改变")
        files["tables/"*rel] = bytes
    end
    function add(rel)
        bytes = read(r6_public_path(source, rel))
        get(meta["snapshot"], rel, "") == bytes2hex(sha256(bytes)) ||
            error("不是报告核验的原值：$rel")
        files[rel] = bytes
    end
    foreach(
        add,
        ["freeze.toml", "freeze.sha256", "source.tar", "selection.toml", "selection.sha256"],
    )
    freeze = TOML.parse(String(copy(files["freeze.toml"])))
    for rel in keys(meta["snapshot"])
        (
            startswith(rel, "policies/") ||
            endswith(rel, "/summary.toml") ||
            startswith(rel, "stress/")
        ) && add(rel)
    end
    root = normpath(joinpath(@__DIR__, ".."))
    protocol = read(joinpath(root, "configs/r6/protocol.toml"))
    bytes2hex(sha256(protocol)) == freeze["sources"]["configs/r6/protocol.toml"] ||
        error("协议不是冻结原版")
    files["protocol.toml"] = protocol
    for name in ("r6_public_report.jl", "r6_study_tables.jl")
        files["code/"*name] = read(joinpath(@__DIR__, name))
    end
    bytes2hex(sha256(files["code/r6_study_tables.jl"])) ==
    meta["reporter_hashes"]["scripts/r6_study_tables.jl"] || error("统计表程序不是原报告版本")
    all(length(bytes) <= 5*1024^2 for bytes in values(files)) || error("单文件超过5 MiB")
    mkpath(output)
    for (rel, bytes) in files
        p = r6_public_path(output, rel)
        mkpath(dirname(p))
        write(p, bytes)
    end
    for (rel, bytes) in r6_public_stress_tables(output)
        write(joinpath(output, rel), bytes)
    end
    m = Dict(
        "schema"=>"r6-public-evidence-v1",
        "origin"=>"synthetic",
        "source_commit"=>meta["source_commit"],
        "batch_id"=>basename(normpath(source)),
        "report_sha256"=>r6_public_hash(joinpath(report, "report.toml")),
        "test_physics_replayed_by_bundle"=>false,
        "stress_physics_replayed_by_bundle"=>true,
        "solver_reexecuted"=>false,
        "files"=>r6_public_inventory(output),
    )
    write(joinpath(output, "public.toml"), r6_public_text(m))
    write(joinpath(output, "public.sha256"), r6_public_hash(joinpath(output, "public.toml"))*"\n")
    println("R6 portable statistical/stress evidence saved; numeric replay still required.")
end

function r6_public_day_validation(r)
    Dict(
        "model_pass"=>r.model_pass,
        "cost_complete"=>r.cost_complete,
        "comfort_outcome"=>r.comfort_outcome,
        "operating_net_cost"=>r.net_cost_USD,
        "peak_excess_K"=>r.peak_excess_K,
        "delivery_budget_pass"=>r.mismatch_MWh<=r.capacity_budget_MWh+1e-6,
        "called_energy_MWh"=>r.called_energy_MWh,
        "mismatch_MWh"=>r.mismatch_MWh,
    )
end
function r6_public_equal(a, b)
    keys(a) == keys(b) || error("统计字段不同")
    for k in keys(a)
        x, y = a[k], b[k]
        if x isa AbstractDict
            r6_public_equal(x, y)
        elseif x isa AbstractFloat && y isa Real
            (isequal(x, y) || isapprox(x, y; atol = 1e-12, rtol = 1e-12)) ||
                error("统计数值不同：$k")
        else
            isequal(x, y) || error("统计/状态不同：$k")
        end
    end
    nothing
end

"""在冻结包内重新计算日统计、验证选择、配对费用及24个压力日的物理/KKT；不求解。"""
function numeric_r6_public(root)
    public = r6_public_manifest(root)
    freeze = TOML.parsefile(joinpath(root, "freeze.toml"))
    meta = TOML.parsefile(joinpath(root, "tables/report.toml"))
    r6_public_hash(joinpath(root, "tables/report.toml")) == public["report_sha256"] ||
        error("报告身份错误")
    r6_public_hash(joinpath(root, "protocol.toml")) ==
    freeze["sources"]["configs/r6/protocol.toml"] || error("统计协议改变")
    meta["source_commit"] == public["source_commit"] == freeze["source_commit"] ||
        error("来源提交不同")
    meta["complete"] === true && meta["origin"] == "synthetic" || error("不是完整合成报告")
    meta["counts"] == Dict("training"=>14, "validation"=>14, "test"=>6, "stress"=>6) ||
        error("报告计数错误")
    for (rel, h) in meta["snapshot"]
        isfile(r6_public_path(root, rel)) &&
            r6_public_hash(r6_public_path(root, rel)) != h &&
            error("原值不是报告来源")
    end
    for (rel, h) in meta["tables"]
        r6_public_hash(r6_public_path(joinpath(root, "tables"), rel)) == h || error("统计源表不同")
    end
    table(name) = collect(CSV.File(joinpath(root, "tables", name)))
    dayfiles = sort(
        filter(f -> startswith(f, "days") && endswith(f, ".csv"), collect(keys(meta["tables"]))),
    )
    days = reduce(vcat, table.(dayfiles))
    length(days) == 13000 || error("验证/测试日记录不完整")
    spec = R6StudySpec(freeze["spec"])
    candidates = r6_study_candidates(spec)
    selected = TOML.parsefile(joinpath(root, "selection.toml"))
    stats = TOML.parsefile(joinpath(root, "protocol.toml"))["statistics"]
    records = Dict{String,Any}()
    rows = NamedTuple[]
    for split in ("validation", "test"), c in candidates
        id = c["id"]
        split == "test" && !(id in [x["candidate_id"] for x in selected["selected"]]) && continue
        rr = filter(x -> x.split == split && x.candidate == id, days)
        length(rr) == (split == "test" ? 1000 : 500) || error("候选日数量错误")
        all(x -> x.method == c["method"], rr) || error("方法标签不同")
        s = r6_summarize_days(
            [x.day_id for x in rr],
            r6_public_day_validation.(rr);
            epsilon = spec.data["epsilon"],
            confidence = spec.data["confidence"],
        )
        original = TOML.parsefile(joinpath(root, split, id, "summary.toml"))
        original["candidate"] == c && original["split"] == split || error("汇总身份错误")
        Set(keys(original["days"])) == Set(x.day_id for x in rr) || error("原日身份不同")
        r6_public_equal(s, original["summary"])
        split == "validation" && (records[id] = original)
        push!(rows, r6_study_summary_row(split, c, s, selected["selected"]))
    end
    r6_public_equal(select_r6_methods(spec, records), selected)
    pairs = r6_study_pair_table(days, spec.data["methods"], stats)
    expected = r6_study_table_bytes(Dict("risk-cost"=>rows, "paired-cost"=>pairs))
    for (rel, bytes) in expected
        bytes == read(joinpath(root, "tables", rel)) || error("统计表不是逐日原值重算：$rel")
    end
    stressrows = NamedTuple[]
    for chosen in selected["selected"]
        id = chosen["candidate_id"]
        c = only(filter(c->c["id"]==id, candidates))
        pdata = TOML.parsefile(joinpath(root, "policies", id*".toml"))
        p = R6Policy(pdata, bytes2hex(sha256(IOBuffer(PaperRebuild.r5_market_text(pdata)))))
        for day in spec.data["stress_cases"]
            v = zeros(2, p.data["physical"]["dispatch"]["T"])
            startswith(day, "clear_") && (
                v[1, :] .=
                    TOML.parsefile(joinpath(root, "protocol.toml"))["generator"]["clear_sky_fraction"]
            )
            v[2, :] .= endswith(day, "_up") ? 1.0 : -1.0
            saved = TOML.parsefile(joinpath(root, "stress", id, "days", day*".toml"))
            r = saved["result"]
            r["source_hashes_at_solve"] == PaperRebuild.r6_evaluation_science_hashes() ||
                error("不是原压力日科学源码")
            check = validate_r6_policy_day(p, v, r)
            thin = Dict(k=>x for (k, x) in check if !(k in ("stage", "request_MW", "delivered_MW")))
            r6_public_equal(thin, saved["validation"])
            push!(stressrows, r6_study_day_row("stress", c, day, thin, r))
        end
    end
    r6_study_table_bytes(Dict("stress"=>stressrows))["stress.csv"] ==
    read(joinpath(root, "tables/stress.csv")) || error("压力表与原值不同")
    for (rel, bytes) in r6_public_stress_tables(root)
        bytes == read(joinpath(root, rel)) || error("逐时图源与原值不同：$rel")
    end
    println(
        "R6 portable replay passed: 13000 daily statistics, 15 cost pairs, 24 raw stress physics/KKT; no optimization.",
    )
end

"""解包已封存源码到临时目录，在Julia子进程核验；不需要旧Git历史、商业许可或本地运行目录。"""
function check_r6_public(root)
    VERSION == v"1.12.6" || error("需要Julia 1.12.6")
    m = r6_public_manifest(root)
    archive = joinpath(root, "source.tar")
    freeze = TOML.parsefile(joinpath(root, "freeze.toml"))
    r6_public_hash(archive) == freeze["archive_sha256"] || error("科学归档错误")
    for h in Tar.list(archive)
        h.type in (:file, :directory) || error("归档类型错误")
        r6_public_path(root, rstrip(h.path, '/'))
    end
    mktempdir() do temp
        Tar.extract(archive, temp)
        r6_public_inventory(temp) == freeze["sources"] || error("归档文件清单不同")
        for name in ("r6_public_report.jl", "r6_study_tables.jl")
            path = joinpath(temp, "scripts", name)
            ispath(path) && error("报告程序与原科学归档冲突")
            cp(joinpath(root, "code", name), path)
        end
        env = copy(ENV)
        sep = Sys.iswindows() ? ';' : ':'
        project = normpath(joinpath(@__DIR__, ".."))
        env["JULIA_DEPOT_PATH"] = join(unique(vcat([joinpath(project, ".julia")], DEPOT_PATH)), sep)
        env["JULIA_LOAD_PATH"] = join(["@", "@stdlib"], sep)
        command = `$(Base.julia_cmd()) --startup-file=no --project=$temp $(joinpath(temp,"scripts/r6_public_report.jl")) numeric $(abspath(root))`
        run(setenv(Cmd(command; dir = temp), env))
    end
    r6_public_manifest(root) == m || error("重验期间证据包改变")
    nothing
end

if abspath(PROGRAM_FILE) == @__FILE__
    length(ARGS) in (2, 4) ||
        error("usage: r6_public_report.jl create <raw> <report> <new-public> | check <public>")
    action = ARGS[1]
    action == "create" && length(ARGS)==4 ? create_r6_public(ARGS[2:4]...) :
    action == "check" && length(ARGS)==2 ? check_r6_public(ARGS[2]) :
    action == "numeric" && length(ARGS)==2 ? numeric_r6_public(ARGS[2]) : error("参数错误")
end
