using PaperRebuild, JuMP, HiGHS, TOML, SHA

const R7_PLAN_ROOT=normpath(joinpath(@__DIR__, ".."))
const R7_PLAN_RECORDS=[
    (case = name, method = method, id = name*"_"*method) for name in ("legacy", "reserve") for
    method in ("extensive", "finite_fault_ccg")
]

function r7_plan_read_frozen(dir)
    # 加载记录自己的科学源码，避免未来工作树变更使原实验失去可重验能力。
    wrapper=Module(gensym(:R7PlanningEvidence))
    Base.include(wrapper, abspath(joinpath(dir, "code/replay.jl")))
    Base.invokelatest(getfield, wrapper, :x)
end

function r7_plan_tables(directory)
    summary=IOBuffer()
    stage=IOBuffer()
    battery=IOBuffer()
    println(
        summary,
        "record,run_id,method,status,model_safe,cost_complete,cost_USD,lower_bound_USD,iterations,elapsed_sec",
    )
    println(
        stage,
        "record,run_id,iteration,master_status,normal_cost_USD,master_bound_USD,model_safe,added_faults",
    )
    println(battery, "record,run_id,scenario,time_h,energy_MWh")
    for entry in R7_PLAN_RECORDS
        x=r7_plan_read_frozen(joinpath(directory, entry.id))
        r=x.result
        q=x.validation
        r["method"]==entry.method || error("记录方法与冻结清单不符")
        println(
            summary,
            join(
                [
                    entry.id,
                    r["run_id"],
                    r["method"],
                    r["status"],
                    q["robust_model_pass"],
                    q["conditional_optimality_pass"],
                    get(q, "cost_USD", ""),
                    get(q, "lower_bound_USD", ""),
                    length(r["iterations"]),
                    r["elapsed_sec"],
                ],
                ',',
            ),
        )
        for (k, it) in enumerate(r["iterations"])
            m=it["master"]
            v=q["iterations"][k]
            println(
                stage,
                join(
                    [
                        entry.id,
                        r["run_id"],
                        k,
                        m["status"],
                        get(v["master"], "cost_USD", ""),
                        get(m, "lower_bound_USD", ""),
                        v["robust_model_pass"],
                        length(it["added_pairs"]),
                    ],
                    ',',
                ),
            )
        end
        if q["robust_model_pass"]
            n=r["iterations"][q["candidate_iteration"]]["master"]["normal"]
            E=PaperRebuild.r7_unpack(n["values"], "E_BES")
            for w in axes(E, 3), t in axes(E, 2)
                println(
                    battery,
                    join(
                        [entry.id, r["run_id"], w, (t-1)*x.case.normal.data["dt_h"], E[2, t, w]],
                        ',',
                    ),
                )
            end
        end
    end
    normal=r7_plan_read_frozen(joinpath(directory, "reserve_normal"))
    E=PaperRebuild.r7_unpack(normal.result["values"], "E_BES")
    for w in axes(E, 3), t in axes(E, 2)
        println(
            battery,
            join(
                [
                    "reserve_normal",
                    normal.result["run_id"],
                    w,
                    (t-1)*normal.case.data["dt_h"],
                    E[2, t, w],
                ],
                ',',
            ),
        )
    end
    Dict(
        "summary.csv"=>String(take!(summary)),
        "stages.csv"=>String(take!(stage)),
        "battery.csv"=>String(take!(battery)),
    )
end

function r7_plan_create(directory)
    ispath(directory)&&error("不覆盖已存在证据包")
    mkpath(directory)
    input=Dict{String,Any}()
    for entry in R7_PLAN_RECORDS
        normal=entry.case=="legacy" ? "normal-hand.toml" : "normal-reserve-hand.toml"
        spec=entry.case=="legacy" ? "planning-hand.toml" : "planning-reserve-hand.toml"
        c=load_r7_planning_case(
            joinpath(R7_PLAN_ROOT, "configs/r7", normal),
            joinpath(R7_PLAN_ROOT, "configs/r7", spec),
        )
        input[entry.id]=Dict("case_sha256"=>c.sha256, "method"=>entry.method, "budget_sec"=>600.0)
    end
    rule=Dict(
        "schema"=>"r7-planning-evidence-v1",
        "origin"=>"synthetic",
        "scope"=>"two_node_analytic_development_evidence",
        "records"=>input,
        "source_hashes"=>PaperRebuild.r7_planning_science_hashes(),
        "analytical_rule"=>TOML.parsefile(
            joinpath(R7_PLAN_ROOT, "configs/r7/reserve-hand-freeze.toml"),
        ),
    )
    open(io->TOML.print(io, rule; sorted = true), joinpath(directory, "rule.toml"), "w")
    optimizer=optimizer_with_attributes(
        HiGHS.Optimizer,
        "threads"=>1,
        "primal_feasibility_tolerance"=>1e-9,
        "dual_feasibility_tolerance"=>1e-9,
        "mip_feasibility_tolerance"=>1e-9,
        "mip_rel_gap"=>1e-9,
    )
    for entry in R7_PLAN_RECORDS
        normal=entry.case=="legacy" ? "normal-hand.toml" : "normal-reserve-hand.toml"
        spec=entry.case=="legacy" ? "planning-hand.toml" : "planning-reserve-hand.toml"
        c=load_r7_planning_case(
            joinpath(R7_PLAN_ROOT, "configs/r7", normal),
            joinpath(R7_PLAN_ROOT, "configs/r7", spec),
        )
        r=solve_r7_planning(c; optimizer, method = Symbol(entry.method), budget_sec = 600)
        save_r7_planning(c, r, joinpath(directory, entry.id))
        println(entry.id, " ", r["status"])
        flush(stdout)
    end
    normal=load_r7_normal_case(joinpath(R7_PLAN_ROOT, "configs/r7/normal-reserve-hand.toml"))
    r=solve_r7_normal(normal; optimizer, budget_sec = 600)
    save_r7_normal(normal, r, joinpath(directory, "reserve_normal"))
    for (file, body) in r7_plan_tables(directory)
        write(joinpath(directory, file), body)
    end
    hashes=Dict(
        replace(relpath(joinpath(p, f), directory), '\\'=>'/')=>bytes2hex(
            sha256(read(joinpath(p, f))),
        ) for (p, _, fs) in walkdir(directory) for f in fs
    )
    open(
        io->TOML.print(io, Dict("files"=>hashes); sorted = true),
        joinpath(directory, "files.toml"),
        "w",
    )
    r7_plan_check(directory)
end

function r7_plan_check(directory)
    hashes=TOML.parsefile(joinpath(directory, "files.toml"))["files"]
    actual=Set(
        replace(relpath(joinpath(p, f), directory), '\\'=>'/') for (p, _, fs) in walkdir(directory)
        for f in fs
    )
    actual==union(Set(keys(hashes)), Set(["files.toml"])) || error("证据包文件集合不符")
    for (p, h) in hashes
        !isabspath(p)&&!occursin(':', p)&&!occursin('\\', p)&&all(
            x->!(x in ("", ".", "..")),
            split(p, '/'),
        ) || error("证据路径非法")
        bytes2hex(sha256(read(joinpath(directory, split(p, '/')...))))==h || error("证据包被篡改")
    end
    rule=TOML.parsefile(joinpath(directory, "rule.toml"))
    rule["schema"]=="r7-planning-evidence-v1"&&rule["origin"]=="synthetic"&&rule["scope"]=="two_node_analytic_development_evidence" ||
        error("研究范围被改写")
    Set(keys(rule["records"]))==Set(e.id for e in R7_PLAN_RECORDS) || error("实验缺项")
    if isfile(joinpath(directory, "continuation.toml"))
        continuation=TOML.parsefile(joinpath(directory, "continuation.toml"))
        continuation["schema"]=="r7-planning-continuation-v1"&&continuation["optimized_again"]===false ||
            error("续接范围错误")
        records=vcat([e.id for e in R7_PLAN_RECORDS], ["reserve_normal"])
        expected=Set(
            p for p in keys(hashes) if p=="rule.toml"||any(id->startswith(p, id*"/"), records)
        )
        Set(keys(continuation["unchanged_files"]))==expected || error("续接原文件清单缺项")
        all(get(hashes, p, "")==h for (p, h) in continuation["unchanged_files"]) ||
            error("续接改变原科学值")
    end
    for e in R7_PLAN_RECORDS
        r=TOML.parsefile(joinpath(directory, e.id, "result.toml"))
        r["case_sha256"]==rule["records"][e.id]["case_sha256"]&&r["method"]==e.method&&r["source_hashes_at_solve"]==rule["source_hashes"] ||
            error("实验不符合冻结规则")
    end
    for (p, text) in r7_plan_tables(directory)
        !isempty(text)&&read(joinpath(directory, p), String)==text || error("原值摘要不一致")
    end
    println(
        "R7 planning development evidence verified from frozen scientific values; no optimization.",
    )
end

# 报告失败后仅同字节续接已有科学记录；不能重新求解以替代原运行。
function r7_plan_finalize(source, destination)
    src=abspath(source)
    dest=abspath(destination)
    ispath(dest)&&error("不覆盖续接目录")
    records=vcat([e.id for e in R7_PLAN_RECORDS], ["reserve_normal"])
    for id in records
        r7_plan_read_frozen(joinpath(src, id))
    end
    original=Dict(
        replace(relpath(joinpath(p, f), src), '\\'=>'/')=>bytes2hex(sha256(read(joinpath(p, f))))
        for id in records for (p, _, fs) in walkdir(joinpath(src, id)) for f in fs
    )
    original["rule.toml"]=bytes2hex(sha256(read(joinpath(src, "rule.toml"))))
    mkpath(dest)
    for id in records
        cp(joinpath(src, id), joinpath(dest, id))
    end
    cp(joinpath(src, "rule.toml"), joinpath(dest, "rule.toml"))
    all(bytes2hex(sha256(read(joinpath(dest, p))))==h for (p, h) in original)||error("续接改变原值")
    continuation=Dict(
        "schema"=>"r7-planning-continuation-v1",
        "optimized_again"=>false,
        "parent_directory_name"=>basename(src),
        "unchanged_files"=>original,
        "reason"=>"报告读取相对include路径失败；仅把冻结源码入口解析为绝对路径，不修改科学模型、输入或原值",
    )
    open(io->TOML.print(io, continuation; sorted = true), joinpath(dest, "continuation.toml"), "w")
    for (p, body) in r7_plan_tables(dest)
        write(joinpath(dest, p), body)
    end
    hashes=Dict(
        replace(relpath(joinpath(p, f), dest), '\\'=>'/')=>bytes2hex(sha256(read(joinpath(p, f))))
        for (p, _, fs) in walkdir(dest) for f in fs
    )
    open(
        io->TOML.print(io, Dict("files"=>hashes); sorted = true),
        joinpath(dest, "files.toml"),
        "w",
    )
    r7_plan_check(dest)
end

if abspath(PROGRAM_FILE)==@__FILE__
    if length(ARGS)==3&&ARGS[1]=="finalize"
        r7_plan_finalize(ARGS[2], ARGS[3])
    elseif length(ARGS)==2&&ARGS[1] in ("create", "check")
        ARGS[1]=="create" ? r7_plan_create(ARGS[2]) : r7_plan_check(ARGS[2])
    else
        error("usage: r7_planning_evidence.jl create|check DIR | finalize SOURCE NEW_DIR")
    end
end
